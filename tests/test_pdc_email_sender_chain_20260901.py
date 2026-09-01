from __future__ import annotations

import importlib.util
from email.message import Message
from pathlib import Path
import unittest

REVIEWER = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/scripts/pdc_email_reviewer.py")
spec = importlib.util.spec_from_file_location("pdc_email_reviewer_auth_contract", REVIEWER)
reviewer = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(reviewer)


class PdcEmailSenderChainVerificationTests(unittest.TestCase):
    def message(self, sender: str, *authentication_results: str, arc_results: tuple[str, ...] = ()) -> Message:
        msg = Message()
        msg["From"] = sender
        for value in authentication_results:
            msg["Authentication-Results"] = value
        for value in arc_results:
            msg["ARC-Authentication-Results"] = value
        return msg

    def test_gmail_receiver_result_accepts_forwarded_microsoft_chain_with_spf_alignment(self):
        msg = self.message(
            "andy.weir@broometoyota.com.au",
            "mx.google.com; dkim=pass header.i=@29714740p.onmicrosoft.com; "
            "arc=pass (i=1 spf=pass spfdomain=broometoyota.com.au "
            "dkim=pass dkdomain=broometoyota.com.au dmarc=pass fromdomain=broometoyota.com.au); "
            "spf=pass (google.com: domain of andy.weir@broometoyota.com.au designates 192.0.2.4 as permitted sender) "
            "smtp.mailfrom=andy.weir@broometoyota.com.au",
            "dkim=none;dmarc=none action=none header.from=broometoyota.com.au;",
            arc_results=(
                "i=2; mx.google.com; arc=pass (i=1 spf=pass spfdomain=broometoyota.com.au "
                "dkim=pass dkdomain=broometoyota.com.au dmarc=pass fromdomain=broometoyota.com.au)",
            ),
        )
        result = reviewer.email_authentication_evidence(msg, reviewer.sender(msg))
        self.assertEqual(
            result,
            {
                "sender_domain": "broometoyota.com.au",
                "gmail_authentication_results": True,
                "spf_aligned": True,
                "dkim_aligned": False,
                "dmarc_aligned": True,
                "aligned": True,
            },
        )

    def test_aligned_requires_receiver_authenticated_result_not_domain_allowlist(self):
        msg = self.message("stephen.peck@pmgwa.com.au")
        result = reviewer.email_authentication_evidence(msg, reviewer.sender(msg))
        self.assertFalse(result["gmail_authentication_results"])
        self.assertFalse(result["aligned"])

    def test_spoofed_from_domain_does_not_inherit_authenticated_sender_chain(self):
        msg = self.message(
            "attacker@pmgwa.com.au.evil.example",
            "mx.google.com; spf=pass smtp.mailfrom=stephen.peck@pmgwa.com.au; "
            "dkim=pass header.d=pmgwa.com.au; dmarc=pass header.from=pmgwa.com.au",
        )
        result = reviewer.email_authentication_evidence(msg, reviewer.sender(msg))
        self.assertFalse(result["spf_aligned"])
        self.assertFalse(result["dkim_aligned"])
        self.assertFalse(result["dmarc_aligned"])
        self.assertFalse(result["aligned"])

    def test_duplicate_google_receiver_results_fail_closed(self):
        msg = self.message(
            "stephen.peck@pmgwa.com.au",
            "mx.google.com; spf=pass smtp.mailfrom=stephen.peck@pmgwa.com.au",
            "mx.google.com; spf=pass smtp.mailfrom=stephen.peck@pmgwa.com.au",
        )
        result = reviewer.email_authentication_evidence(msg, reviewer.sender(msg))
        self.assertFalse(result["gmail_authentication_results"])
        self.assertFalse(result["aligned"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
