# Zebra label printing

This build prints raw ZPL through QZ Tray. The QZ browser connector is bundled locally in `vendor/qz/qz-tray.js`; the printing PC still needs the QZ Tray desktop application installed and running.

## Printing PC setup

1. Install QZ Tray on the Windows PC and leave it running in the notification area.
2. Install the Zebra printer in Windows and confirm it can print a test label.
3. Prefer one of these printer names: `BT-Zebra-EricComp`, `dc-01\BT-Zebra-EricComp`, or `192.168.0.164`.
4. Open the website through `start-preview.bat` or the hosted HTTPS site.
5. On the first label print, approve the website when QZ Tray asks for access.

If none of the preferred names exists, the website uses the first installed printer whose name contains Zebra, ZDesigner, or BT-Zebra. It never silently sends ZPL to an unrelated single printer.

## Operator workflow

- Click **Label** on a vehicle row or vehicle detail card to print that vehicle.
- Tick multiple vehicle rows to reveal **Print Labels** and print the selection.
- After scanning an Autocare despatch notice, the matched vehicle is recorded as arrived at PMB; accept the immediate print prompt or use **Print labels from this notice**, **Print not-in-system only**, or the individual **Print label** buttons.
- For an Autocare vehicle not in the CRM, enter a customer name or leave it blank to print `(Dealer Order)`.

The website warns before printing when a VIN is not 17 characters or is missing WMI, VDS Number, or Frame. The operator can cancel or knowingly continue.

Each vehicle creates one 68 mm × 45 mm ZPL block (`^PW540`, `^LL360`) and the printer produces two identical labels through `^PQ2`.

## Troubleshooting

- **QZ Tray browser connector did not load:** reload the page and confirm `vendor/qz/qz-tray.js` is present.
- **Connection failed:** start QZ Tray, then try the Label button again.
- **Zebra printer not found:** check the Windows printer name and confirm the printer is installed on that PC.
- **Approval prompt:** approve the site in QZ Tray. Unsigned requests may require user approval.
- Use the hidden **Zebra Label Printing** troubleshooting screen to preview/copy ZPL when diagnosing a label layout or data issue.
