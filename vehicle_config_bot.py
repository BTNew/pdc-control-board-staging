"""Credential-free, fail-closed processing core for Vehicle Config CSV files.

Every proposal is typed, evidence-bound, and validated before any output is written.
XLSX mutation intentionally fails closed: OOXML package preservation has not yet been
proven, and loading/saving with a workbook library can silently rewrite unrelated XML.
"""
from __future__ import annotations

import csv
import io
import math
import os
import re
import tempfile
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from enum import Enum
from pathlib import Path
from typing import Any, Iterable, Sequence

ALLOWED_FIELDS = frozenset({"Hidden", "Cost", "Sell"})
REVOLUTION_CSV_HEADER = (
    "Type",
    "Franchise_Id",
    "Range_Id",
    "Model_Id",
    "Accessory_Id",
    "Hidden",
    "Franchise_Description",
    "Range_Description",
    "Model_Description",
    "Accessory_Description",
    "Cost",
    "Sell",
    "Colour",
    "Trim",
    "Operation_Id",
)
PRIVILEGED_COMMANDS = frozenset({"remember", "correct", "disable", "undo"})


class VehicleConfigError(Exception):
    """Base error for a rejected Vehicle Config operation."""


class UnsupportedFormatError(VehicleConfigError):
    pass


class ValidationError(VehicleConfigError):
    pass


class AuthorizationError(VehicleConfigError):
    pass


class TaxSemantics(str, Enum):
    NOT_APPLICABLE = "not-applicable"
    EX_GST = "ex-gst"
    INC_GST = "inc-gst"


_FIELD_TAX = {
    "Hidden": TaxSemantics.NOT_APPLICABLE,
    "Cost": TaxSemantics.EX_GST,
    "Sell": TaxSemantics.INC_GST,
}


@dataclass(frozen=True)
class ProposalEvidence:
    """Immutable provenance for one proposed value."""

    source: str
    reference: str
    authorizer: str
    tax_semantics: TaxSemantics

    def __post_init__(self) -> None:
        for name in ("source", "reference", "authorizer"):
            value = getattr(self, name)
            if not isinstance(value, str) or not value.strip():
                raise ValidationError(f"evidence {name} must be non-empty")
        if not isinstance(self.tax_semantics, TaxSemantics):
            raise ValidationError("evidence tax_semantics must be a TaxSemantics value")

    @property
    def authorized_identity(self) -> str:
        """The immutable identity that authorized this evidence."""
        return self.authorizer


@dataclass(frozen=True)
class CellChange:
    """A typed, evidence-bound edit to one existing CSV data cell."""

    row: int
    field: str
    value: str | Decimal
    evidence: ProposalEvidence
    sheet: str | None = None

    def __post_init__(self) -> None:
        if self.field not in ALLOWED_FIELDS:
            raise ValidationError(f"field {self.field!r} is not editable")
        if isinstance(self.row, bool) or not isinstance(self.row, int) or self.row < 1:
            raise ValidationError("row must be a one-based positive integer")
        if not isinstance(self.evidence, ProposalEvidence):
            raise ValidationError("change requires ProposalEvidence")
        expected = _FIELD_TAX[self.field]
        if self.evidence.tax_semantics is not expected:
            raise ValidationError(f"{self.field} requires {expected.value} tax semantics")
        if self.field == "Hidden":
            if not isinstance(self.value, str):
                raise ValidationError("Hidden must be yes or no")
            normalized = self.value.strip().lower()
            if normalized not in {"yes", "no"}:
                raise ValidationError("Hidden must be yes or no")
            object.__setattr__(self, "value", normalized)
        else:
            object.__setattr__(self, "value", _plain_amount(self.value, self.field))


@dataclass(frozen=True)
class ApprovedAmount:
    """An immutable approved amount plus its scoped provenance."""

    amount: Decimal | int | float
    source: str
    reference: str
    authorized_identity: str
    tax_semantics: TaxSemantics

    def __post_init__(self) -> None:
        object.__setattr__(self, "amount", _plain_amount(self.amount, "amount"))
        ProposalEvidence(self.source, self.reference, self.authorized_identity, self.tax_semantics)


@dataclass(frozen=True)
class HiluxGvmEvidence:
    model: str
    amount_inc_gst: Decimal | int | float
    source: str
    reference: str
    authorized_identity: str

    def __post_init__(self) -> None:
        if not isinstance(self.model, str) or not self.model.strip():
            raise ValidationError("Hilux GVM evidence requires a model")
        if "hilux" not in " ".join(self.model.lower().split()):
            raise ValidationError("Hilux GVM evidence must be scoped to a Hilux model")
        object.__setattr__(self, "amount_inc_gst", _plain_amount(self.amount_inc_gst, "Hilux GVM amount"))
        ProposalEvidence(self.source, self.reference, self.authorized_identity, TaxSemantics.INC_GST)


@dataclass(frozen=True)
class ParsedCommand:
    action: str
    argument: str = ""
    requires_authorized_identity: bool = False


@dataclass(frozen=True)
class PricingResult:
    cost_ex_gst: Decimal
    sell_inc_gst: Decimal
    solis_applied: bool
    hilux_gvm_inc_gst: Decimal
    base_sell_reference: str


FREIGHT_COST_EX_GST = {
    "kununurra": Decimal("830.00"), "halls creek": Decimal("830.00"),
    "fitzroy crossing": Decimal("830.00"), "derby": Decimal("600.00"),
}


def _plain_amount(value: Any, name: str) -> Decimal:
    """Accept only actual finite, non-negative numeric objects (never strings/bools)."""
    if isinstance(value, bool) or not isinstance(value, (int, float, Decimal)):
        raise ValidationError(f"{name} must be a plain numeric value")
    if isinstance(value, float) and not math.isfinite(value):
        raise ValidationError(f"{name} must be finite and non-negative")
    try:
        result = Decimal(str(value))
    except (InvalidOperation, ValueError) as exc:
        raise ValidationError(f"{name} must be a plain numeric value") from exc
    if not result.is_finite() or result < 0:
        raise ValidationError(f"{name} must be finite and non-negative")
    return result.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def calculate_pmb_sell(cost: ApprovedAmount) -> Decimal:
    if not isinstance(cost, ApprovedAmount) or cost.tax_semantics is not TaxSemantics.EX_GST:
        raise ValidationError("PMB cost requires approved ex-GST evidence")
    return (cost.amount * Decimal("1.10") * Decimal("1.10")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def calculate_freight(destination: str) -> tuple[Decimal, Decimal]:
    key = " ".join(str(destination).strip().lower().split())
    if key not in FREIGHT_COST_EX_GST:
        raise ValidationError("freight destination has no approved price evidence")
    cost = FREIGHT_COST_EX_GST[key]
    return cost, (cost * Decimal("1.20") * Decimal("1.10")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def approved_pd_pricing() -> tuple[Decimal, Decimal]:
    return Decimal("300.00"), Decimal("1995.00")


def calculate_pricing(*, cost: ApprovedAmount, base_sell: ApprovedAmount,
                      solis: bool = False, hilux_gvm: HiluxGvmEvidence | None = None) -> PricingResult:
    """Recompute from immutable base evidence; Solis is therefore added exactly once."""
    if not isinstance(cost, ApprovedAmount) or cost.tax_semantics is not TaxSemantics.EX_GST:
        raise ValidationError("cost requires approved ex-GST base evidence")
    if not isinstance(base_sell, ApprovedAmount) or base_sell.tax_semantics is not TaxSemantics.INC_GST:
        raise ValidationError("sell requires approved inc-GST base evidence")
    if not isinstance(solis, bool):
        raise ValidationError("solis must be boolean")
    if hilux_gvm is not None and not isinstance(hilux_gvm, HiluxGvmEvidence):
        raise ValidationError("Hilux GVM requires scoped evidence")
    gvm = hilux_gvm.amount_inc_gst if hilux_gvm else Decimal("0.00")
    sell = base_sell.amount + (Decimal("150.00") if solis else 0) + gvm
    return PricingResult(cost.amount, sell.quantize(Decimal("0.01")), solis, gvm, base_sell.reference)


def parse_command(text: str, *, authorized_identity: str | None = None) -> ParsedCommand:
    normalized = " ".join(text.strip().split())
    match = re.fullmatch(r"(?i)(show\s+unresolved|review|apply|explain|remember|correct|disable|undo)(?:\s+(.*))?", normalized)
    if not match:
        raise ValidationError("unsupported command")
    action = match.group(1).lower()
    action = "show unresolved" if action.startswith("show") else action
    argument = match.group(2) or ""
    privileged = action in PRIVILEGED_COMMANDS
    if privileged and not (authorized_identity and authorized_identity.strip()):
        raise AuthorizationError(f"{action.title()} requires an authorized identity")
    return ParsedCommand(action, argument, privileged)


def execute_privileged_stub(command: ParsedCommand) -> None:
    if command.action not in PRIVILEGED_COMMANDS:
        raise ValidationError("not a privileged command")
    raise VehicleConfigError(f"{command.action.title()} is not configured; an authorized credential-backed adapter is required")


def _require_changes(changes: Iterable[CellChange]) -> tuple[CellChange, ...]:
    result = tuple(changes)
    seen: set[tuple[int, str]] = set()
    for change in result:
        if not isinstance(change, CellChange):
            raise ValidationError("all changes must be CellChange proposals")
        if change.sheet is not None:
            raise ValidationError("sheet is unsupported because XLSX mutation is disabled")
        key = (change.row, change.field)
        if key in seen:
            raise ValidationError(f"duplicate change target: {key}")
        seen.add(key)
    return result


def apply_file(source: str | os.PathLike[str], destination: str | os.PathLike[str], changes: Iterable[CellChange]) -> None:
    src, dst = Path(source), Path(destination)
    if not src.is_file():
        raise ValidationError(f"source does not exist: {src}")
    requested = _require_changes(changes)
    if src.suffix.lower() == ".xlsx":
        raise UnsupportedFormatError("XLSX mutation is disabled until exact OOXML preservation is proven")
    if src.suffix.lower() != ".csv":
        raise UnsupportedFormatError("only CSV is currently supported")
    if dst.resolve() == src.resolve():
        raise ValidationError("source and destination must differ; retain the original and write a separate reviewed file")
    if dst.exists():
        raise ValidationError("destination already exists")
    dst.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".vehicle-config-", suffix=".csv", dir=dst.parent)
    os.close(fd)
    temp = Path(name)
    try:
        _apply_csv(src, temp, requested)
        _validate_csv(src, temp, requested)
        os.replace(temp, dst)
    except Exception:
        temp.unlink(missing_ok=True)
        raise


def _csv_document(path: Path) -> tuple[str, csv.Dialect, list[list[str]]]:
    raw = path.read_bytes()
    encoding = "utf-8-sig" if raw.startswith(b"\xef\xbb\xbf") else "utf-8"
    text = raw.decode(encoding)
    try:
        dialect = csv.Sniffer().sniff(text[:8192], delimiters=",;\t|")
    except csv.Error:
        dialect = csv.excel
    return encoding, dialect, list(csv.reader(io.StringIO(text, newline=""), dialect))


def _require_revolution_header(rows: Sequence[Sequence[str]]) -> None:
    if not rows:
        raise ValidationError("CSV has no header row")
    header = tuple(rows[0])
    if header != REVOLUTION_CSV_HEADER:
        raise ValidationError(
            "CSV header must exactly match the canonical Revolution 15-column schema "
            "in name and order"
        )


def _apply_csv(src: Path, out: Path, changes: Sequence[CellChange]) -> None:
    encoding, dialect, rows = _csv_document(src)
    _require_revolution_header(rows)
    header = rows[0]
    for row_number, row in enumerate(rows[1:], start=1):
        if len(row) != len(header):
            raise ValidationError(f"data row {row_number} has a different column count")
    indexes = {name: index for index, name in enumerate(header)}
    for change in changes:
        if change.field not in indexes:
            raise ValidationError(f"missing required header: {change.field}")
        if change.row >= len(rows):
            raise ValidationError(f"data row {change.row} does not exist")
        rows[change.row][indexes[change.field]] = str(change.value)
    newline = "\r\n" if b"\r\n" in src.read_bytes() else "\n"
    with out.open("w", encoding=encoding, newline="") as handle:
        csv.writer(handle, delimiter=dialect.delimiter, quotechar=dialect.quotechar,
                   escapechar=dialect.escapechar, doublequote=dialect.doublequote,
                   quoting=dialect.quoting, lineterminator=newline).writerows(rows)


def _validate_csv(before: Path, after: Path, changes: Sequence[CellChange]) -> None:
    _, _, old = _csv_document(before)
    _, _, new = _csv_document(after)
    _require_revolution_header(old)
    _require_revolution_header(new)
    if len(old) != len(new) or any(len(a) != len(b) for a, b in zip(old, new)):
        raise ValidationError("CSV structure changed")
    if not old or old[0] != new[0]:
        raise ValidationError("CSV headers or column order changed")
    width = len(old[0])
    for label, rows in (("source", old), ("output", new)):
        for row_number, row in enumerate(rows[1:], start=1):
            if len(row) != width:
                raise ValidationError(f"{label} data row {row_number} has a different column count")
    targets = {(c.row, old[0].index(c.field)): str(c.value) for c in changes}
    for (row, col), approved_value in targets.items():
        if new[row][col] != approved_value:
            raise ValidationError(
                f"CSV target mismatch at row {row}, column {col + 1}: output does not equal approved value"
            )
    for r, (old_row, new_row) in enumerate(zip(old, new)):
        for col, (a, b) in enumerate(zip(old_row, new_row)):
            if a != b and (r, col) not in targets:
                raise ValidationError(f"unauthorized CSV change at row {r}, column {col + 1}")


def review_file(path: str | os.PathLike[str], changes: Iterable[CellChange]) -> tuple[CellChange, ...]:
    requested = _require_changes(changes)
    src = Path(path)
    fd, name = tempfile.mkstemp(suffix=src.suffix)
    os.close(fd)
    temp = Path(name)
    temp.unlink(missing_ok=True)
    try:
        apply_file(src, temp, requested)
    finally:
        temp.unlink(missing_ok=True)
    return requested
