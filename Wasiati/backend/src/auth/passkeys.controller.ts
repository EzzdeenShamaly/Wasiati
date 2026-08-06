import { Body, Controller, Post, Req, Res, UseGuards } from '@nestjs/common';
import { ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { Request, Response } from 'express';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { PasskeysService } from './passkeys.service';
import { TokenService } from './token.service';
import { AuthCookieService } from './auth-cookie.service';
import { PasskeyRegisterVerifyDto, PasskeyLoginVerifyDto } from './dto/passkey.dto';

@ApiTags('passkeys')
@Controller('auth/passkeys')
export class PasskeysController {
  constructor(
    private passkeys: PasskeysService,
    private tokens: TokenService,
    private cookies: AuthCookieService,
  ) {}

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('register/options')
  registerOptions(@CurrentUser() user: { userId: string }) {
    return this.passkeys.generateRegistrationOptions(user.userId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('register/verify')
  registerVerify(@CurrentUser() user: { userId: string }, @Body() body: PasskeyRegisterVerifyDto) {
    return this.passkeys.verifyRegistration(user.userId, body.sessionId, body.response);
  }

  // Public — used before the user is logged in (that's the point of passkey login)
  @Post('login/options')
  loginOptions() {
    return this.passkeys.generateAuthenticationOptions();
  }

  @Post('login/verify')
  async loginVerify(
    @Body() body: PasskeyLoginVerifyDto,
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    const { user } = await this.passkeys.verifyAuthentication(body.sessionId, body.response);
    const pair = await this.tokens.issueTokenPair(user, {
      userAgent: req.headers['user-agent'],
      ipAddress: req.ip,
    });
    return this.cookies.deliver(req, res, pair);
  }
}
