import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import * as express from 'express';
import * as cookieParser from 'cookie-parser';
import helmet from 'helmet';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { Logger } from 'nestjs-pino';
import { AppModule } from './app.module';
import { deploymentRegion, REGION_CURRENCY, resolveBillingCurrency } from './common/geo.util';

async function bootstrap() {
  // Fail fast: this instance serves exactly one region and writes to that region's
  // database. A missing or bogus REGION would silently file users in the wrong
  // jurisdiction, so refuse to start rather than risk it.
  const region = deploymentRegion();

  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  app.useLogger(app.get(Logger));

  // Behind Cloudflare -> ALB, `req.ip` without this is the load balancer's private
  // address — for EVERY request. That is not cosmetic here: req.ip is written into
  // executed wills' signature certificates (will-document.service.ts), stamped on
  // audit logs and trustee confirmations, and keys the global rate limit — which
  // collapses into one shared bucket when every caller "is" 10.0.x.x.
  //
  // TRUST_PROXY_HOPS counts the proxies WE operate in front of the app (prod:
  // Cloudflare + ALB = 2; bare ALB = 1; local dev: unset = 0, express default).
  // A hop COUNT, never `true`: `trust proxy = true` believes the entire
  // X-Forwarded-For chain, which lets any client prepend a forged IP.
  const hops = Number(process.env.TRUST_PROXY_HOPS);
  if (Number.isFinite(hops) && hops > 0) {
    app.getHttpAdapter().getInstance().set('trust proxy', hops);
  }

  // Webhook signature verification needs the RAW body, so these routes
  // must bypass Nest's default JSON body parser. Registered before the rest
  // of the app sets up its own body parsing.
  app.use('/payments/webhook', express.raw({ type: 'application/json' }));
  app.use('/identity/webhook', express.raw({ type: 'application/json' }));

  app.use(
    helmet({
      // The will PDF is served from api.wasiati.com and embedded by app.wasiati.com
      // (a different origin). Helmet's default CORP: same-origin would block that.
      crossOriginResourcePolicy: { policy: 'cross-origin' },
    }),
  );
  app.use(cookieParser());
  // whitelist:true strips any property not declared on a DTO, which already blocks
  // mass assignment (no DTO exposes a privilege field). forbidNonWhitelisted (hard
  // 400 on extras) is deliberately NOT enabled: it would break any client that sends
  // a field the DTO doesn't declare, and the security gain over stripping is nil.
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
  app.enableCors({
    origin: process.env.CORS_ORIGIN?.split(',').map((s) => s.trim()) ?? ['http://localhost:3000'],
    credentials: true,
  });

  // API docs expose every route, including /admin/*. Never serve them in production.
  if (process.env.NODE_ENV !== 'production') {
    const config = new DocumentBuilder()
      .setTitle('Wasiati API')
      .setDescription('Backend API for Wasiati — digital will & legacy platform')
      .setVersion('0.1')
      .addBearerAuth()
      .build();
    const document = SwaggerModule.createDocument(app, config);
    SwaggerModule.setup('docs', app, document);
  }

  const port = process.env.PORT ?? 4000;
  await app.listen(port);
  const billing = resolveBillingCurrency(region);
  const fallback = billing !== REGION_CURRENCY[region] ? ` (fallback from ${REGION_CURRENCY[region]})` : '';
  console.log(`Wasiati API — region ${region}, billing in ${billing}${fallback} — running on port ${port}`);
}
bootstrap();
