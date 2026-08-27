from __future__ import annotations
import importlib.util
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('campaign_mapping',ROOT/'scripts/run_authenticated_acceptance_campaign_686_staging.py');campaign=importlib.util.module_from_spec(spec);assert spec and spec.loader;spec.loader.exec_module(campaign)
class AcceptancePlannerMappingTests(unittest.TestCase):
 def test_sublet_booking_scheduled_is_mapped_to_reviewed_planner_vocabulary(self):
  candidate={'evidence_refs':['body'],'instruction_id':'body-1','interpreted_text':'Sublet booking scheduled 2026-09-16 for Job Card PDC686-X-SB'}
  self.assertEqual(campaign.planner_text_for_candidate(candidate),'Sublet book scheduled 2026-09-16 for Job Card PDC686-X-SB')
  self.assertEqual(candidate['interpreted_text'],'Sublet booking scheduled 2026-09-16 for Job Card PDC686-X-SB')
 def test_exact_duplicate_body_and_attachment_actions_map_once(self):
  actions=[
   {'vehicle_id':'vehicle-1','action_type':'parts_complete','target':{'parts.complete':True},'expected':{'parts.complete':True},'evidence_refs':['body'],'instruction_ids':['body-1']},
   {'vehicle_id':'vehicle-1','action_type':'parts_complete','target':{'parts.complete':True},'expected':{'parts.complete':True},'evidence_refs':['attachment:fixture'],'instruction_ids':['attachment-1']},
  ]
  result=campaign.dedupe_planned_actions(actions)
  self.assertEqual(len(result),1)
  self.assertEqual(result[0]['instruction_ids'],['body-1'])
if __name__=='__main__':unittest.main()
