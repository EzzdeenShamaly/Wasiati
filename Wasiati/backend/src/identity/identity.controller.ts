import { Controller, Get, Headers, Post, Req, UseGuards } from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation, ApiExcludeEndpoint } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { IdentityService } from './identity.service';

// NOTE: the guard is applied per-method, not on the class: the provider webhook is
// called server-to-server and carries a signature, not a bearer token.
@ApiTags('identity')
@Controller('identity')
export class IdentityController {
  constructor(private identity: IdentityService) {}

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('verification-session')
  @ApiOperation({
    summary: 'Start an ID-verification session; returns a hosted URL. 503 until a KYC vendor is configured.',
  })
  createSession(@CurrentUser() user: { userId: string }) {
    return this.identity.createSession(user.userId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Get('status')
  @ApiOperation({ summary: "The user's ID-verification status, and whether verification is available at all." })
  status(@CurrentUser() user: { userId: string }) {
    return this.identity.status(user.userId);
  }

  /**
   * KYC vendor events. Public by necessity, authenticated by an HMAC over the RAW
   * body — main.ts registers express.raw for this exact path, so `req.body` is a
   * Buffer and must not be JSON-parsed before it reaches us (re-serialising it would
   * change the bytes and break every signature).
   *
   * Each vendor names its own header: Stripe sends `Stripe-Signature`, Sumsub sends
   * `x-payload-digest` (+ `x-payload-digest-alg`). Exactly one provider is active, and
   * a request only carries its own header, so taking whichever is present is
   * unambiguous. The active adapter is what actually verifies it; a header meant for
   * the other vendor simply fails verification, which is the correct outcome.
   */
  @Post('webhook')
  @ApiExcludeEndpoint()
  webhook(
    @Req() req: any,
    @Headers('stripe-signature') stripeSignature: string,
    @Headers('x-payload-digest') sumsubDigest: string,
    @Headers('x-payload-digest-alg') algorithm: string,
  ) {
    return this.identity.handleWebhook(req.body, stripeSignature || sumsubDigest, algorithm);
  }
}
