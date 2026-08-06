import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

/**
 * The "Save & sign" payload for a directive (POA or HCD). Unlike the heir
 * registry there is no half-filled draft to preserve: the only action the UI
 * offers is save-and-sign, and it stays disabled until every field is filled —
 * so the agent fields are REQUIRED here, not permissive. `wishes` is the HCD's
 * treatment-wishes text; the service enforces its presence per type (required
 * for HCD, ignored for POA) because a DTO can't see the route param.
 */
export class SaveDirectiveDto {
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  agentName: string;

  @IsString()
  @MinLength(1)
  @MaxLength(40)
  agentPhone: string;

  @IsString()
  @MinLength(1)
  @MaxLength(200)
  agentEmail: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  wishes?: string;
}
