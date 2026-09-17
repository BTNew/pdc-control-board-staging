import copy,unittest,json,tempfile,os
from pathlib import Path
import pmb_arb_estimates as arb
# Use the private real index when explicitly configured; otherwise a minimal
# fitting-evidence fixture tests the rules without publishing the catalogue.
_fixture=tempfile.TemporaryDirectory()
arb.CATALOGUE_DIRECTORY=Path(os.environ.get('ARB_REFERENCE_DIRECTORY',_fixture.name))
if 'ARB_REFERENCE_DIRECTORY' not in os.environ:
 (arb.CATALOGUE_DIRECTORY/arb.CATALOGUES[arb.GUIDE_VERSION][0]).write_text(json.dumps(dict(guide_version=arb.GUIDE_VERSION,guide_sha256=arb.GUIDE_SHA256,pages=[dict(page=56,text='SS223HF 320.00 SS223HP 400.00')])) )

class Estimates(unittest.TestCase):
 def row(self,**kw):
  r=dict(operation_description='Safari Snorkel',source_estimated_hours=0,effective_estimated_hours=0,proposed_station='FITTING',hours_provenance='source_explicit',vehicle_context=dict(source='unique_current_exact_stock_navision',vehicle='HiLux WorkMate',production_month='06/26'))
  r.update(kw);return r
 def test_generic_my26(self):
  r=arb.finalize_rows([self.row()])[0];self.assertEqual(r['effective_estimated_hours'],2.25);self.assertEqual(r['hours_provenance'],'ai_estimated');self.assertEqual(r['source_estimated_hours'],0);self.assertTrue(arb.validate(r))
 def test_exact_variants(self):
  for name,h in [('Safari Snorkel V-Spec',2),('Safari Snorkel ARMAX',2.5)]: self.assertEqual(arb.finalize_rows([self.row(operation_description=name)])[0]['effective_estimated_hours'],h)
 def test_unknown_or_older_generation(self):
  for ctx in [{},dict(source='email_received_date',vehicle='HiLux',production_month='06/26'),dict(source='unique_current_exact_stock_navision',vehicle='HiLux',production_month='06/24')]:
   with self.assertRaises(ValueError):arb.finalize_rows([self.row(vehicle_context=ctx)])
 def test_staff_and_source_protected(self):
  for patch in [dict(source_estimated_hours=3,effective_estimated_hours=3),dict(staff_hours=0),dict(proposed_station='SUBLET'),dict(hours_provenance='craig_special',effective_estimated_hours=4),dict(hours_provenance='explicit_description_time',effective_estimated_hours=1)]:
   r=self.row(**patch);self.assertEqual(arb.finalize_rows([r])[0],r)
 def test_generic_unable_does_not_block_match(self):
  r=self.row(arb_review=dict(status='unable',reason='No fitting hours found'))
  self.assertEqual(arb.finalize_rows([r])[0]['effective_estimated_hours'],2.25)
 def test_generic_unable_without_research_rejected(self):
  a=dict(status='unable',checked=True,guide_version=arb.GUIDE_VERSION,guide_sha256=arb.GUIDE_SHA256,searched_terms=['custom'],match_basis='Searched the guide for this description',reason='No comparable catalogue fitting allowance')
  with self.assertRaises(ValueError):arb.finalize_rows([self.row(operation_description='Custom kit',arb_review=a)])
 def test_interpreted_unable_accepted(self):
  a=dict(status='unable',checked=True,guide_version=arb.GUIDE_VERSION,guide_sha256=arb.GUIDE_SHA256,searched_terms=['custom'],match_basis='Custom fabrication has no matching manufactured kit',reason='One-off tray fabrication drawing and scope required',unable_reason_code='unsupported_product',reviewed_candidates=[],vehicle_context=dict(source='source_report',model='Unknown'))
  self.assertEqual(arb.finalize_rows([self.row(operation_description='Custom kit',arb_review=a)])[0]['hours_provenance'],'estimate_unable')
 def test_138_retains_bus(self):
  r=arb.finalize_rows([self.row(proposed_station='BUS_4X4',department='138')])[0];self.assertEqual(r['proposed_station'],'BUS_4X4');self.assertEqual(r['effective_estimated_hours'],2.25)
 def test_out_of_tolerance(self):
  r=arb.finalize_rows([self.row()])[0];r['effective_estimated_hours']=4;self.assertFalse(arb.validate(r))
 def test_no_double_count_kit_guess(self):
  with self.assertRaises(ValueError):arb.finalize_rows([self.row(operation_description='Snorkel and winch kit')])

if __name__=='__main__':unittest.main()

