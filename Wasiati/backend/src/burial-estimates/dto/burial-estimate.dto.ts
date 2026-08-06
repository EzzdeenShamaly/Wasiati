import { IsString, IsNumber, IsOptional, IsIn, Min, Max } from 'class-validator';

export class CreateBurialEstimateDto {
  @IsString()
  city: string;

  @IsNumber()
  @Min(0)
  baseAmount: number;

  @IsIn(['USD', 'CAD'])
  currency: 'USD' | 'CAD';

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(20)
  inflationRatePercent?: number;

  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(50)
  projectionYears?: number;
}

export class SubmitManualQuoteDto {
  @IsNumber()
  @Min(0)
  amount: number;

  @IsOptional()
  @IsString()
  notes?: string;
}
