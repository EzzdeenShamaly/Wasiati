import { Module } from '@nestjs/common';
import { PortalController } from './portal.controller';
import { PortalService } from './portal.service';
// AuthModule for OtpService (the portal sign-in code), FilesModule for the legacy-video
// presign, WillsModule for WillDocumentService (the released will as a PDF — same renderer
// as the owner's export, so the two documents can never drift apart). ClaimTokenGuard is
// provided here as well as in DeathClaimsModule: it is the same CLASS either way — Nest
// instantiates one per module, and the guard is stateless, so both read the same
// @ClaimScopes metadata key and the same tokenHash column.
import { AuthModule } from '../auth/auth.module';
import { FilesModule } from '../files/files.module';
import { WillsModule } from '../wills/wills.module';
import { ClaimTokenGuard } from '../death-claims/claim-token.guard';

@Module({
  imports: [AuthModule, FilesModule, WillsModule],
  controllers: [PortalController],
  providers: [PortalService, ClaimTokenGuard],
  exports: [PortalService],
})
export class PortalModule {}
