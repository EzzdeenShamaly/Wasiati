import { AiToolSpec } from './ai-provider.interface';

/**
 * The extraction target, expressed in the TYPED FORM'S OWN VOCABULARY.
 *
 * This is the load-bearing decision of the whole feature. The wizard does not collect
 * a list of heirs — it collects **counters** ("how many sons?", "is your mother
 * living?") and then derives the heir set itself in `_buildHeirs`, applying the ḥijb
 * (blocking) rules on the way: a grandfather only counts when there is no father, a
 * paternal grandmother only when neither parent survives.
 *
 * The previous extraction asked the model for a flat `[{relation, name}]` list, which
 * let it produce heir sets the form cannot: a grandfather beside a living father, the
 * eleven relation codes with no control in the form, real names in a slot the form
 * fills with "Son 1". Every one of those was a fara'id input the user could never have
 * entered by hand.
 *
 * Extracting the counters instead makes that class of bug unreachable rather than
 * policed. The values here are exactly the ones `draftState` carries, with exactly the
 * bounds the form's own steppers enforce, so anything Ameen captures is something the
 * user could have clicked — and the form, not this service, still derives the heirs.
 */

/** Mirrors the wizard's stepper bounds (`asInt(v, 0, 20)`; wives capped at 4). */
export const COUNTER_MAX = 20;
export const WIVES_MAX = 4;

/** The two schools the picker actually offers (DECISIONS §20). */
export const MADHHABS = ['JUMHUR', 'HANAFI'] as const;

const counter = (description: string, max = COUNTER_MAX) => ({
  type: 'integer',
  minimum: 0,
  maximum: max,
  description,
});

const flag = (description: string) => ({ type: 'boolean', description });

export const INTAKE_TOOL: AiToolSpec = {
  name: 'record_will_intake_data',
  description:
    'Records everything learned about the family so far, as running totals. Call this on EVERY turn with the complete picture, not just the newest detail — later calls replace earlier ones.',
  parameters: {
    type: 'object',
    properties: {
      sex: {
        type: 'string',
        enum: ['male', 'female'],
        description: "The person making the will. Decides whether a spouse is recorded as wives or a husband.",
      },
      wives: counter('Number of living wives. Only for a male testator.', WIVES_MAX),
      husband: flag('True if the testator is female and her husband is living.'),
      sons: counter('Number of living sons.'),
      daughters: counter('Number of living daughters.'),
      mother: flag('True if the testator’s mother is living.'),
      father: flag('True if the testator’s father is living.'),
      grandfather: flag('True if the paternal grandfather is living.'),
      gmMaternal: flag('True if the maternal grandmother is living.'),
      gmPaternal: flag('True if the paternal grandmother is living.'),
      brothers: counter('Number of living full brothers.'),
      sisters: counter('Number of living full sisters.'),
      uncles: counter('Number of living paternal uncles.'),
      cousins: counter('Number of living paternal cousins.'),
      madhhab: {
        type: 'string',
        enum: [...MADHHABS],
        description: 'Only if the user states a preference. JUMHUR is the majority position; do not ask unprompted.',
      },
      readyToFinalize: flag('True only once the user confirms the family details are complete and correct.'),
    },
  },
};

/** The shape the wizard's `draftState` understands, plus our own bookkeeping. */
export interface IntakeSeed {
  sex: 'male' | 'female';
  wives: number;
  husband: boolean;
  sons: number;
  daughters: number;
  mother: boolean;
  father: boolean;
  grandfather: boolean;
  gmMaternal: boolean;
  gmPaternal: boolean;
  brothers: number;
  sisters: number;
  uncles: number;
  cousins: number;
  madhhab?: string;
  readyToFinalize?: boolean;
  /** Set once this intake has been handed to the wizard, so it cannot be handed twice. */
  seededWillId?: string;
}

const int = (v: unknown, max: number): number => {
  const n = typeof v === 'number' ? Math.trunc(v) : Number.NaN;
  if (!Number.isFinite(n)) return 0;
  return Math.min(Math.max(n, 0), max);
};
const bool = (v: unknown): boolean => v === true;

/**
 * Clamps whatever the model returned into something the form could have produced.
 *
 * A second line of defence, not the only one: the tool schema already declares the
 * bounds. Models are not bound by a schema they merely received, so the numbers are
 * clamped again here — the same `asInt(v, 0, 20)` the wizard applies when it restores
 * a draft. Nothing downstream ever sees an out-of-range value.
 */
export function normalizeSeed(raw: Record<string, any> | null | undefined, prior?: IntakeSeed): IntakeSeed {
  const r = raw ?? {};
  const sex: 'male' | 'female' = r.sex === 'female' ? 'female' : 'male';
  const madhhab = (MADHHABS as readonly string[]).includes(r.madhhab) ? r.madhhab : prior?.madhhab;
  return {
    sex,
    // A wife count on a female testator (or a husband on a male one) is not something
    // the form can represent — the spouse control switches on sex — so drop it rather
    // than carry a contradiction into the fara'id engine.
    wives: sex === 'male' ? int(r.wives, WIVES_MAX) : 0,
    husband: sex === 'female' ? bool(r.husband) : false,
    sons: int(r.sons, COUNTER_MAX),
    daughters: int(r.daughters, COUNTER_MAX),
    mother: bool(r.mother),
    father: bool(r.father),
    grandfather: bool(r.grandfather),
    gmMaternal: bool(r.gmMaternal),
    gmPaternal: bool(r.gmPaternal),
    brothers: int(r.brothers, COUNTER_MAX),
    sisters: int(r.sisters, COUNTER_MAX),
    uncles: int(r.uncles, COUNTER_MAX),
    cousins: int(r.cousins, COUNTER_MAX),
    ...(madhhab ? { madhhab } : {}),
    readyToFinalize: bool(r.readyToFinalize),
    ...(prior?.seededWillId ? { seededWillId: prior.seededWillId } : {}),
  };
}

/** True when there is at least one heir — the wizard's own gate for leaving step 1. */
export function hasAnyHeir(s: IntakeSeed): boolean {
  return (
    s.wives > 0 || s.husband || s.sons > 0 || s.daughters > 0 || s.mother || s.father ||
    s.grandfather || s.gmMaternal || s.gmPaternal ||
    s.brothers > 0 || s.sisters > 0 || s.uncles > 0 || s.cousins > 0
  );
}
