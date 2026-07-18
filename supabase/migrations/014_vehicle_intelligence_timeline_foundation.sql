begin;

-- Vehicle intelligence / email-timeline shared foundation.
-- Builds on the existing AI intake tables from 004_ai_intake_foundation.sql.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ai_email_relevance_status') THEN
    CREATE TYPE public.ai_email_relevance_status AS ENUM ('relevant', 'not_relevant', 'needs_review');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ai_review_decision_status') THEN
    CREATE TYPE public.ai_review_decision_status AS ENUM ('pending', 'approved', 'partially_approved', 'rejected', 'irrelevant', 'corrected');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'vehicle_timeline_source_kind') THEN
    CREATE TYPE public.vehicle_timeline_source_kind AS ENUM ('email', 'supplier', 'manual', 'system', 'workshop', 'ai', 'import');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'vehicle_timeline_event_state') THEN
    CREATE TYPE public.vehicle_timeline_event_state AS ENUM ('confirmed', 'calculated', 'predicted', 'manual');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.monitored_mailboxes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mailbox_key text NOT NULL UNIQUE,
  display_name text NOT NULL,
  mailbox_address text NOT NULL,
  provider text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  test_mode boolean NOT NULL DEFAULT true,
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid REFERENCES auth.users(id),
  updated_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT monitored_mailboxes_key_lower CHECK (mailbox_key = lower(mailbox_key)),
  CONSTRAINT monitored_mailboxes_address_lower CHECK (mailbox_address = lower(mailbox_address))
);

ALTER TABLE public.ai_email_intake
  ADD COLUMN IF NOT EXISTS monitored_mailbox_id uuid REFERENCES public.monitored_mailboxes(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS recipient_mailbox text,
  ADD COLUMN IF NOT EXISTS provider_message_link text;

CREATE TABLE IF NOT EXISTS public.ai_email_analysis_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  intake_id uuid NOT NULL REFERENCES public.ai_email_intake(id) ON DELETE CASCADE,
  analysis_version integer NOT NULL DEFAULT 1,
  relevance_status public.ai_email_relevance_status NOT NULL DEFAULT 'needs_review',
  normalized_subject text,
  normalized_sender text,
  normalized_thread_context text,
  new_content_text text,
  ai_summary text,
  classifications jsonb NOT NULL DEFAULT '[]'::jsonb,
  extracted_facts jsonb NOT NULL DEFAULT '{}'::jsonb,
  analysis_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  warnings text[] NOT NULL DEFAULT '{}',
  vehicle_match_confidence numeric(4,3),
  relevance_confidence numeric(4,3),
  classification_confidence numeric(4,3),
  action_confidence numeric(4,3),
  confidence_label text NOT NULL DEFAULT 'manual_review_required',
  auto_action_allowed boolean NOT NULL DEFAULT false,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ai_email_analysis_results_unique_version UNIQUE (intake_id, analysis_version),
  CONSTRAINT ai_email_analysis_results_confidence_bounds CHECK (
    (vehicle_match_confidence IS NULL OR vehicle_match_confidence BETWEEN 0 AND 1) AND
    (relevance_confidence IS NULL OR relevance_confidence BETWEEN 0 AND 1) AND
    (classification_confidence IS NULL OR classification_confidence BETWEEN 0 AND 1) AND
    (action_confidence IS NULL OR action_confidence BETWEEN 0 AND 1)
  ),
  CONSTRAINT ai_email_analysis_results_label_check CHECK (confidence_label IN ('high_confidence', 'review_recommended', 'manual_review_required'))
);

CREATE INDEX IF NOT EXISTS ai_email_analysis_results_intake_idx
  ON public.ai_email_analysis_results(intake_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ai_email_analysis_results_relevance_idx
  ON public.ai_email_analysis_results(relevance_status, created_at DESC);

CREATE TABLE IF NOT EXISTS public.vehicle_match_candidates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  analysis_result_id uuid NOT NULL REFERENCES public.ai_email_analysis_results(id) ON DELETE CASCADE,
  vehicle_id uuid REFERENCES public.vehicles(id) ON DELETE SET NULL,
  candidate_rank integer NOT NULL,
  match_type text NOT NULL,
  matched_value text,
  score numeric(4,3),
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_primary boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT vehicle_match_candidates_rank_positive CHECK (candidate_rank > 0),
  CONSTRAINT vehicle_match_candidates_score_bounds CHECK (score IS NULL OR score BETWEEN 0 AND 1),
  CONSTRAINT vehicle_match_candidates_unique_rank UNIQUE (analysis_result_id, candidate_rank)
);

CREATE INDEX IF NOT EXISTS vehicle_match_candidates_analysis_idx
  ON public.vehicle_match_candidates(analysis_result_id, candidate_rank);
CREATE INDEX IF NOT EXISTS vehicle_match_candidates_vehicle_idx
  ON public.vehicle_match_candidates(vehicle_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.ai_review_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  intake_id uuid REFERENCES public.ai_email_intake(id) ON DELETE CASCADE,
  analysis_result_id uuid REFERENCES public.ai_email_analysis_results(id) ON DELETE CASCADE,
  primary_vehicle_id uuid REFERENCES public.vehicles(id) ON DELETE SET NULL,
  selected_vehicle_id uuid REFERENCES public.vehicles(id) ON DELETE SET NULL,
  status public.ai_review_decision_status NOT NULL DEFAULT 'pending',
  review_reason text NOT NULL,
  review_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  proposed_changes jsonb NOT NULL DEFAULT '{}'::jsonb,
  proposed_action_ids uuid[] NOT NULL DEFAULT '{}',
  candidate_vehicle_ids uuid[] NOT NULL DEFAULT '{}',
  decision_notes text,
  approval_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  reviewed_by uuid REFERENCES auth.users(id),
  reviewed_at timestamptz,
  created_by uuid REFERENCES auth.users(id),
  updated_by uuid REFERENCES auth.users(id),
  version integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ai_review_items_version_positive CHECK (version > 0)
);

CREATE INDEX IF NOT EXISTS ai_review_items_status_idx
  ON public.ai_review_items(status, created_at DESC);
CREATE INDEX IF NOT EXISTS ai_review_items_vehicle_idx
  ON public.ai_review_items(COALESCE(selected_vehicle_id, primary_vehicle_id), created_at DESC);
CREATE INDEX IF NOT EXISTS ai_review_items_intake_idx
  ON public.ai_review_items(intake_id);

CREATE TABLE IF NOT EXISTS public.vehicle_timeline_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  event_at timestamptz NOT NULL DEFAULT now(),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  source_kind public.vehicle_timeline_source_kind NOT NULL,
  event_state public.vehicle_timeline_event_state NOT NULL DEFAULT 'confirmed',
  source_system text,
  source_mailbox text,
  source_email_id text,
  source_thread_id text,
  sender_name text,
  sender_email text,
  recipient_mailbox text,
  supplier_name text,
  subject text,
  ai_summary text,
  original_statement text,
  structured_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  vehicle_match_confidence numeric(4,3),
  relevance_confidence numeric(4,3),
  classification_confidence numeric(4,3),
  action_confidence numeric(4,3),
  confidence_label text NOT NULL DEFAULT 'manual_review_required',
  automatic_update boolean NOT NULL DEFAULT false,
  previous_values jsonb NOT NULL DEFAULT '{}'::jsonb,
  new_values jsonb NOT NULL DEFAULT '{}'::jsonb,
  approval_status text,
  evidence_reference text,
  source_intake_id uuid REFERENCES public.ai_email_intake(id) ON DELETE SET NULL,
  source_analysis_result_id uuid REFERENCES public.ai_email_analysis_results(id) ON DELETE SET NULL,
  review_item_id uuid REFERENCES public.ai_review_items(id) ON DELETE SET NULL,
  correction_of_event_id uuid REFERENCES public.vehicle_timeline_events(id) ON DELETE SET NULL,
  supersedes_event_id uuid REFERENCES public.vehicle_timeline_events(id) ON DELETE SET NULL,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT vehicle_timeline_events_confidence_bounds CHECK (
    (vehicle_match_confidence IS NULL OR vehicle_match_confidence BETWEEN 0 AND 1) AND
    (relevance_confidence IS NULL OR relevance_confidence BETWEEN 0 AND 1) AND
    (classification_confidence IS NULL OR classification_confidence BETWEEN 0 AND 1) AND
    (action_confidence IS NULL OR action_confidence BETWEEN 0 AND 1)
  ),
  CONSTRAINT vehicle_timeline_events_label_check CHECK (confidence_label IN ('high_confidence', 'review_recommended', 'manual_review_required'))
);

CREATE INDEX IF NOT EXISTS vehicle_timeline_events_vehicle_idx
  ON public.vehicle_timeline_events(vehicle_id, event_at DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS vehicle_timeline_events_intake_idx
  ON public.vehicle_timeline_events(source_intake_id);
CREATE INDEX IF NOT EXISTS vehicle_timeline_events_review_idx
  ON public.vehicle_timeline_events(review_item_id);

CREATE TABLE IF NOT EXISTS public.vehicle_intelligence_revisions (
  vehicle_id uuid PRIMARY KEY REFERENCES public.vehicles(id) ON DELETE CASCADE,
  revision bigint NOT NULL DEFAULT 1,
  updated_by uuid REFERENCES auth.users(id),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT vehicle_intelligence_revisions_positive CHECK (revision > 0)
);

CREATE TABLE IF NOT EXISTS public.vehicle_intelligence_summaries (
  vehicle_id uuid PRIMARY KEY REFERENCES public.vehicles(id) ON DELETE CASCADE,
  revision bigint NOT NULL DEFAULT 1,
  summary_text text,
  summary_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  latest_event_id uuid REFERENCES public.vehicle_timeline_events(id) ON DELETE SET NULL,
  latest_rebuilt_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT vehicle_intelligence_summaries_positive CHECK (revision > 0)
);

CREATE TABLE IF NOT EXISTS public.vehicle_eta_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
  source_intake_id uuid REFERENCES public.ai_email_intake(id) ON DELETE SET NULL,
  source_timeline_event_id uuid REFERENCES public.vehicle_timeline_events(id) ON DELETE SET NULL,
  eta_type text NOT NULL,
  eta_value date,
  eta_value_text text,
  eta_state public.vehicle_timeline_event_state NOT NULL DEFAULT 'confirmed',
  confidence numeric(4,3),
  original_wording text,
  source_label text,
  supplier_name text,
  received_at timestamptz,
  previous_eta_id uuid REFERENCES public.vehicle_eta_history(id) ON DELETE SET NULL,
  superseded_by uuid REFERENCES public.vehicle_eta_history(id) ON DELETE SET NULL,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT vehicle_eta_history_confidence_bounds CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1)
);

CREATE INDEX IF NOT EXISTS vehicle_eta_history_vehicle_idx
  ON public.vehicle_eta_history(vehicle_id, created_at DESC);
CREATE INDEX IF NOT EXISTS vehicle_eta_history_active_idx
  ON public.vehicle_eta_history(vehicle_id, eta_type, created_at DESC)
  WHERE superseded_by IS NULL;

CREATE TABLE IF NOT EXISTS public.email_response_drafts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
  intake_id uuid REFERENCES public.ai_email_intake(id) ON DELETE SET NULL,
  analysis_result_id uuid REFERENCES public.ai_email_analysis_results(id) ON DELETE SET NULL,
  review_item_id uuid REFERENCES public.ai_review_items(id) ON DELETE SET NULL,
  source_timeline_event_id uuid REFERENCES public.vehicle_timeline_events(id) ON DELETE SET NULL,
  request_type text NOT NULL,
  requested_by_name text,
  requested_by_email text,
  subject text NOT NULL,
  draft_body text NOT NULL,
  structured_context jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'draft',
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  edited_by uuid REFERENCES auth.users(id),
  edited_at timestamptz,
  sent_by uuid REFERENCES auth.users(id),
  sent_at timestamptz,
  created_by uuid REFERENCES auth.users(id),
  updated_by uuid REFERENCES auth.users(id),
  version integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT email_response_drafts_status_check CHECK (status IN ('draft', 'approved', 'edited', 'rejected', 'sent')),
  CONSTRAINT email_response_drafts_version_positive CHECK (version > 0)
);

CREATE INDEX IF NOT EXISTS email_response_drafts_vehicle_idx
  ON public.email_response_drafts(vehicle_id, created_at DESC);
CREATE INDEX IF NOT EXISTS email_response_drafts_status_idx
  ON public.email_response_drafts(status, created_at DESC);

CREATE TRIGGER monitored_mailboxes_set_updated_at
BEFORE UPDATE ON public.monitored_mailboxes
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER ai_review_items_set_updated_at
BEFORE UPDATE ON public.ai_review_items
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER vehicle_intelligence_summaries_set_updated_at
BEFORE UPDATE ON public.vehicle_intelligence_summaries
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER email_response_drafts_set_updated_at
BEFORE UPDATE ON public.email_response_drafts
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.monitored_mailboxes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_email_analysis_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_match_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_review_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_timeline_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_intelligence_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_intelligence_summaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_eta_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_response_drafts ENABLE ROW LEVEL SECURITY;

-- Summary rows are sanitized and may be viewed directly by viewer+ users.
DROP POLICY IF EXISTS vehicle_intelligence_summaries_select_viewer ON public.vehicle_intelligence_summaries;
CREATE POLICY vehicle_intelligence_summaries_select_viewer
ON public.vehicle_intelligence_summaries
FOR SELECT TO authenticated
USING (public.is_pdc_role('viewer'));

DROP POLICY IF EXISTS monitored_mailboxes_select_operator ON public.monitored_mailboxes;
CREATE POLICY monitored_mailboxes_select_operator
ON public.monitored_mailboxes
FOR SELECT TO authenticated
USING (public.is_pdc_role('operator'));

DROP POLICY IF EXISTS ai_email_analysis_results_select_operator ON public.ai_email_analysis_results;
CREATE POLICY ai_email_analysis_results_select_operator
ON public.ai_email_analysis_results
FOR SELECT TO authenticated
USING (public.is_pdc_role('operator'));

DROP POLICY IF EXISTS vehicle_match_candidates_select_operator ON public.vehicle_match_candidates;
CREATE POLICY vehicle_match_candidates_select_operator
ON public.vehicle_match_candidates
FOR SELECT TO authenticated
USING (public.is_pdc_role('operator'));

DROP POLICY IF EXISTS ai_review_items_select_operator ON public.ai_review_items;
CREATE POLICY ai_review_items_select_operator
ON public.ai_review_items
FOR SELECT TO authenticated
USING (public.is_pdc_role('operator'));

DROP POLICY IF EXISTS email_response_drafts_select_operator ON public.email_response_drafts;
CREATE POLICY email_response_drafts_select_operator
ON public.email_response_drafts
FOR SELECT TO authenticated
USING (public.is_pdc_role('operator'));

-- Direct browser writes stay blocked; service_role / protected RPCs remain the only write path.
REVOKE INSERT, UPDATE, DELETE ON TABLE
  public.monitored_mailboxes,
  public.ai_email_analysis_results,
  public.vehicle_match_candidates,
  public.ai_review_items,
  public.vehicle_timeline_events,
  public.vehicle_intelligence_revisions,
  public.vehicle_intelligence_summaries,
  public.vehicle_eta_history,
  public.email_response_drafts
FROM anon, authenticated;

ALTER PUBLICATION supabase_realtime ADD TABLE public.ai_review_items;
ALTER PUBLICATION supabase_realtime ADD TABLE public.vehicle_intelligence_revisions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.vehicle_intelligence_summaries;

COMMIT;
