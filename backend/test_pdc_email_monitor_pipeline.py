import unittest
from backend.pdc_email_monitor_pipeline import execute_retained_intake
from backend.pdc_jobcard_runtime_client import ATTEST_RPC,PROCESS_RPC
from backend.pdc_communication_runtime_client import PROCESS_COMMUNICATION_RPC

H='a'*64;D='b'*64;A='11111111-1111-4111-8111-111111111111'
AUTH={'dkim_aligned':True,'dmarc_aligned':True,'gmail_authentication_results':True,'sender_domain':'broometoyota.com.au','spf_aligned':True}
def base(kind):
 return {'intake_id':'22222222-2222-4222-8222-222222222222','expected_source_hash':H,'kind':kind,'provider':{'attachment_id':A,'attachment_source_hash':D,'provider_message_id':'<m@example.com>','provider_authserv_id':'mx.google.com','authentication':AUTH}}
class Client:
 def __init__(self,authority,bearer,replies,calls):self.authority,self.bearer,self.replies,self.calls=authority,bearer,list(replies),calls
 def rpc(self,name,payload):self.calls.append((self.authority,name,payload));return self.replies.pop(0)
class PipelineTests(unittest.TestCase):
 def clients(self,actor_replies):
  calls=[];return Client('service_role','service',[{'ok':True,'code':'provider_observation_attested'}],calls),Client('authenticated_monitor','actor',actor_replies,calls),calls
 def test_parts_communication_dispatches_two_authority_action(self):
  s,a,c=self.clients([{'ok':True,'code':'communication_applied','data':{'receipt_id':'r','vehicle_id':'v','action_count':1}}]);item=base('communication');item['retained_text']='Stock 12657478. Parts Complete.'
  result=execute_retained_intake(s,a,item);self.assertTrue(result['ok']);self.assertEqual([x[1] for x in c],[ATTEST_RPC,PROCESS_COMMUNICATION_RPC])
 def test_unknown_or_ambiguous_text_is_review_only_and_makes_no_rpc(self):
  s,a,c=self.clients([]);item=base('communication');item['retained_text']='Please sort this out.'
  result=execute_retained_intake(s,a,item);self.assertFalse(result['ok']);self.assertEqual(result['phase'],'review_required');self.assertFalse(result['mutation_attempted']);self.assertFalse(result['message_sent']);self.assertEqual(c,[])
 def test_relative_sublet_date_is_review_only(self):
  s,a,c=self.clients([]);item=base('communication');item['retained_text']='Stock 12657478. Sublet booked tomorrow.'
  result=execute_retained_intake(s,a,item);self.assertIn('sublet_booking_date_missing_or_ambiguous',result['review_reasons']);self.assertEqual(c,[])
 def test_jobcard_uses_existing_canonical_path(self):
  s,a,c=self.clients([{'ok':True,'code':'jobcard_attachment_receipt','data':{'operation_count':1}}]);item=base('jobcard');item['extraction']={'authentication':AUTH,'canonical_attachment_id':A,'canonical_document_hash':D,'contract_version':'pmb-email-work-v2','email_vehicle':{'stock_numbers':['12657478'],'job_card_number':'J1'},'operation_lines':[{'x':1}],'required_work':['fitting']}
  result=execute_retained_intake(s,a,item);self.assertTrue(result['ok']);self.assertEqual([x[1] for x in c],[ATTEST_RPC,PROCESS_RPC])
if __name__=='__main__':unittest.main()
