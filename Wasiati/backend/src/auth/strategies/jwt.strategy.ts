import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get<string>('SESSION_SECRET'),
      // Pin the algorithm so a token can't be presented with a different/none alg.
      algorithms: ['HS256'],
    });
  }

  async validate(payload: { sub: string; email: string; region: string; role: string }) {
    return { userId: payload.sub, email: payload.email, region: payload.region, role: payload.role };
  }
}
