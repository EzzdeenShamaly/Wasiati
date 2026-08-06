import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { Observable, tap } from 'rxjs';
import { AuditService } from './audit.service';

const MUTATING = new Set(['POST', 'PATCH', 'PUT', 'DELETE']);

/**
 * Automatically records privileged admin mutations (POST/PATCH/PUT/DELETE on
 * /admin/*) to the audit trail on success. Feature modules can also call
 * AuditService.log directly for domain events (releases, KYC decisions, etc.).
 */
@Injectable()
export class AuditInterceptor implements NestInterceptor {
  constructor(private audit: AuditService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const req = context.switchToHttp().getRequest();
    const method: string = req.method;
    const path: string = req.route?.path ?? req.originalUrl ?? req.url ?? '';
    const shouldAudit = MUTATING.has(method) && path.includes('/admin');

    return next.handle().pipe(
      tap(() => {
        if (!shouldAudit) return;
        const user = req.user;
        void this.audit.log({
          actorId: user?.userId,
          actorRole: user?.role,
          action: `${method} ${path}`,
          ipAddress: req.ip,
          userAgent: req.headers?.['user-agent'],
          region: user?.region,
          metadata: { params: req.params, query: req.query },
        });
      }),
    );
  }
}
