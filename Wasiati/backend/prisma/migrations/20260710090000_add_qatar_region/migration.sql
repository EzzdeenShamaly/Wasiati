-- Qatar becomes a first-class region: its own deployment, its own database, and
-- QAR billing (with a USD fallback when QAR is not enabled on the merchant account).
ALTER TYPE "Region" ADD VALUE 'QA';
