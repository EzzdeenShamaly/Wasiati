import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { DirectivesService } from './directives.service';
import { DirectivesController } from './directives.controller';

// PrismaService, AuditService and EntitlementsService/FeatureGuard all come from
// their @Global modules; only the auth guard's module needs importing.
@Module({
  imports: [AuthModule],
  controllers: [DirectivesController],
  providers: [DirectivesService],
  exports: [DirectivesService],
})
export class DirectivesModule {}
