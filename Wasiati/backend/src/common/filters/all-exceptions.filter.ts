import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Response } from 'express';

/**
 * Normalises every error into a safe JSON shape and guarantees no internal detail
 * (Prisma messages, stack traces, driver errors) is ever forwarded to a client.
 *
 *  - HttpException: passed through (its message is intentional and user-facing).
 *  - Prisma known errors: mapped to a sensible status with a GENERIC message —
 *    the raw Prisma text can reveal table/column names and query internals.
 *  - Anything else: 500 with a generic message; the real error is logged server-side.
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('ExceptionFilter');

  catch(exception: unknown, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse<Response>();

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const body = exception.getResponse();
      res.status(status).json(typeof body === 'string' ? { statusCode: status, message: body } : body);
      return;
    }

    if (exception instanceof Prisma.PrismaClientKnownRequestError) {
      const { status, message } = this.mapPrisma(exception);
      this.logger.warn(`Prisma ${exception.code}: ${exception.message}`);
      res.status(status).json({ statusCode: status, message });
      return;
    }

    // Unknown / unexpected: log the real thing, tell the client nothing specific.
    this.logger.error(exception instanceof Error ? exception.stack ?? exception.message : String(exception));
    res.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      statusCode: HttpStatus.INTERNAL_SERVER_ERROR,
      message: 'Internal server error',
    });
  }

  private mapPrisma(e: Prisma.PrismaClientKnownRequestError): { status: number; message: string } {
    switch (e.code) {
      case 'P2002': // unique constraint
        return { status: HttpStatus.CONFLICT, message: 'That record already exists.' };
      case 'P2025': // not found
        return { status: HttpStatus.NOT_FOUND, message: 'Not found.' };
      case 'P2003': // FK constraint
        return { status: HttpStatus.BAD_REQUEST, message: 'That operation references something that does not exist.' };
      default:
        return { status: HttpStatus.BAD_REQUEST, message: 'The request could not be processed.' };
    }
  }
}
