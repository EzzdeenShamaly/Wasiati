-- Negative ledger rows (credit spent at checkout) deserve their own reason
-- rather than being mislabelled as a manual adjustment.
ALTER TYPE "CreditReason" ADD VALUE 'PURCHASE_APPLIED';
