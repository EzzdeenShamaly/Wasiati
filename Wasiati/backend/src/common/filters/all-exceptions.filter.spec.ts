import { BadRequestException, HttpStatus } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AllExceptionsFilter } from './all-exceptions.filter';

/**
 * The filter is the last line against leaking internals. It must pass HttpExceptions
 * through untouched, map Prisma errors to safe generic messages, and turn anything
 * unexpected into a bare 500 — never a stack trace or a driver message.
 */
function makeHost() {
  const json = jest.fn();
  const status = jest.fn().mockReturnValue({ json });
  const host: any = { switchToHttp: () => ({ getResponse: () => ({ status }) }) };
  return { host, status, json };
}

const prismaError = (code: string) =>
  new Prisma.PrismaClientKnownRequestError('unique constraint failed on the fields: (`email`)', {
    code,
    clientVersion: 'test',
  });

describe('AllExceptionsFilter', () => {
  const filter = new AllExceptionsFilter();

  it('passes an HttpException through with its intended status + message', () => {
    const { host, status, json } = makeHost();
    filter.catch(new BadRequestException('Bad thing'), host);
    expect(status).toHaveBeenCalledWith(HttpStatus.BAD_REQUEST);
    expect(json).toHaveBeenCalledWith(expect.objectContaining({ message: 'Bad thing' }));
  });

  it('maps a Prisma unique violation to 409 with a GENERIC message (no column names)', () => {
    const { host, status, json } = makeHost();
    filter.catch(prismaError('P2002'), host);
    expect(status).toHaveBeenCalledWith(HttpStatus.CONFLICT);
    const body = json.mock.calls[0][0];
    expect(body.message).toBe('That record already exists.');
    // The raw Prisma text (which names the `email` column) must NOT leak.
    expect(JSON.stringify(body)).not.toMatch(/email|constraint|fields/i);
  });

  it('maps a Prisma not-found to 404', () => {
    const { host, status } = makeHost();
    filter.catch(prismaError('P2025'), host);
    expect(status).toHaveBeenCalledWith(HttpStatus.NOT_FOUND);
  });

  it('turns an UNEXPECTED error into a bare 500 with no detail or stack', () => {
    const { host, status, json } = makeHost();
    const boom = new Error('DB password is hunter2 at /secret/path');
    filter.catch(boom, host);
    expect(status).toHaveBeenCalledWith(HttpStatus.INTERNAL_SERVER_ERROR);
    const body = json.mock.calls[0][0];
    expect(body).toEqual({ statusCode: 500, message: 'Internal server error' });
    // The real message (and any stack) is never forwarded to the client.
    expect(JSON.stringify(body)).not.toMatch(/hunter2|secret|password/i);
  });

  it('does not leak a raw string thrown as an exception', () => {
    const { host, json } = makeHost();
    filter.catch('raw internal string with a token abc123', host);
    expect(JSON.stringify(json.mock.calls[0][0])).not.toMatch(/abc123|token/i);
  });
});
