from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Literal, Optional

ModuleGroup = Literal["pp", "tl", "pl"]


@dataclass(frozen=True)
class ModuleSpec:
    id: str
    group: ModuleGroup
    title: str
    scanpy_qualname: str
    color_hex: str


@dataclass
class ModuleInstance:
    spec: ModuleSpec
    params: Dict[str, Any] = field(default_factory=dict)

    def run(self, adata: Any) -> None:
        if self.spec.id == "pp.filter_cells":
            _run_filter_cells(adata, self.params)
            return
        if self.spec.id == "pp.filter_genes":
            _run_filter_genes(adata, self.params)
            return
        if self.spec.id == "pp.scrublet":
            _run_scrublet(adata, self.params)
            return
        if self.spec.id == "pp.calculate_qc_metrics":
            _run_calculate_qc_metrics(adata, self.params)
            return
        if self.spec.id == "pp.normalize_total":
            _run_normalize_total(adata, self.params)
            return
        if self.spec.id == "pp.log1p":
            _run_log1p(adata)
            return
        raise NotImplementedError(self.spec.id)


def _parse_csv_list(value: str) -> List[str]:
    return [x.strip() for x in value.split(",") if x.strip()]


def _parse_int_list(value: str) -> Optional[List[int]]:
    items = _parse_csv_list(value)
    if not items:
        return None
    return [int(x) for x in items]


def _run_filter_cells(adata: Any, params: Dict[str, Any]) -> None:
    import scanpy as sc  # local import so env vars can be set first

    min_genes = int(params.get("min_genes", 100))
    sc.pp.filter_cells(adata, min_genes=min_genes)


def _run_filter_genes(adata: Any, params: Dict[str, Any]) -> None:
    import scanpy as sc  # local import so env vars can be set first

    min_cells = int(params.get("min_cells", 3))
    sc.pp.filter_genes(adata, min_cells=min_cells)


def _run_scrublet(adata: Any, params: Dict[str, Any]) -> None:
    import scanpy as sc  # local import so env vars can be set first

    batch_key_raw = params.get("batch_key", "sample")
    batch_key = str(batch_key_raw).strip() if batch_key_raw is not None else ""
    sc.pp.scrublet(adata, batch_key=batch_key or None)


def _run_calculate_qc_metrics(adata: Any, params: Dict[str, Any]) -> None:
    import scanpy as sc  # local import so env vars can be set first

    use_mt = bool(params.get("use_mt", True))
    use_ribo = bool(params.get("use_ribo", True))
    use_hb = bool(params.get("use_hb", True))
    percent_top_raw = str(params.get("percent_top", "") or "").strip()
    log1p = bool(params.get("log1p", True))

    percent_top = _parse_int_list(percent_top_raw)

    qc_vars: List[str] = []
    if use_mt:
        adata.var["mt"] = adata.var_names.str.startswith("MT-")
        qc_vars.append("mt")
    if use_ribo:
        adata.var["ribo"] = adata.var_names.str.startswith(("RPS", "RPL"))
        qc_vars.append("ribo")
    if use_hb:
        adata.var["hb"] = adata.var_names.str.contains(r"^HB[^(P)]", regex=True, na=False)
        qc_vars.append("hb")

    kwargs: Dict[str, Any] = {
        "adata": adata,
        "qc_vars": qc_vars,
        "log1p": log1p,
        "inplace": True,
    }
    if percent_top is not None:
        kwargs["percent_top"] = percent_top

    sc.pp.calculate_qc_metrics(**kwargs)


def _run_normalize_total(adata: Any, params: Dict[str, Any]) -> None:
    import scanpy as sc  # local import so env vars can be set first

    target_sum_raw = params.get("target_sum", "")
    target_sum_str = str(target_sum_raw).strip() if target_sum_raw is not None else ""
    if target_sum_str:
        sc.pp.normalize_total(adata, target_sum=float(target_sum_str))
    else:
        sc.pp.normalize_total(adata)


def _run_log1p(adata: Any) -> None:
    import scanpy as sc  # local import so env vars can be set first

    sc.pp.log1p(adata)


def available_modules() -> List[ModuleSpec]:
    return [
        ModuleSpec(
            id="pp.filter_cells",
            group="pp",
            title="Filter Cells",
            scanpy_qualname="scanpy.pp.filter_cells",
            color_hex="#2D6CDF",
        ),
        ModuleSpec(
            id="pp.filter_genes",
            group="pp",
            title="Filter Genes",
            scanpy_qualname="scanpy.pp.filter_genes",
            color_hex="#2D6CDF",
        ),
        ModuleSpec(
            id="pp.scrublet",
            group="pp",
            title="Scrublet (Doublet Detection)",
            scanpy_qualname="scanpy.pp.scrublet",
            color_hex="#2D6CDF",
        ),
        ModuleSpec(
            id="pp.calculate_qc_metrics",
            group="pp",
            title="Calculate QC Metrics",
            scanpy_qualname="scanpy.pp.calculate_qc_metrics",
            color_hex="#2D6CDF",
        ),
        ModuleSpec(
            id="pp.normalize_total",
            group="pp",
            title="Normalize Total Counts",
            scanpy_qualname="scanpy.pp.normalize_total",
            color_hex="#2D6CDF",
        ),
        ModuleSpec(
            id="pp.log1p",
            group="pp",
            title="Log1p",
            scanpy_qualname="scanpy.pp.log1p",
            color_hex="#2D6CDF",
        ),
    ]
