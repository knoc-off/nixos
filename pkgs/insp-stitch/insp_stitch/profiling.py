"""Lightweight nested timing + metric collection shared across the pipeline.

Two jobs:
  1. `span()` context manager builds a call tree with per-node total time and
     call count, so "where does the time go" is answerable at sub-stage
     granularity (render -> build_maps/remap, blend -> harmonize/multiband, ...).
  2. `metric()` records named scalars (e.g. per-seam flow residual) attached to
     the currently-open span, so quality diagnostics live next to the timing
     that produced them.

Disabled profilers are near-free: `span()` still times (cheap) but `report()`
is only ever printed on demand, and metric recording is a dict append.
"""
from __future__ import annotations

import time
from contextlib import contextmanager
from dataclasses import dataclass, field


@dataclass
class _Node:
    label: str
    total: float = 0.0
    count: int = 0
    children: dict = field(default_factory=dict)
    metrics: list = field(default_factory=list)  # list[(name, value, unit)]


class Profiler:
    """Collects a tree of timed spans and attached metrics."""

    def __init__(self, enabled: bool = True):
        self.enabled = enabled
        self.root = _Node("total")
        self._stack = [self.root]

    @contextmanager
    def span(self, label: str):
        parent = self._stack[-1]
        node = parent.children.get(label)
        if node is None:
            node = _Node(label)
            parent.children[label] = node
        self._stack.append(node)
        start = time.perf_counter()
        try:
            yield node
        finally:
            node.total += time.perf_counter() - start
            node.count += 1
            self._stack.pop()

    def metric(self, name: str, value, unit: str = "") -> None:
        """Attach a named scalar to the currently-open span."""
        self._stack[-1].metrics.append((name, value, unit))

    # -- reporting -----------------------------------------------------------

    def report(self) -> str:
        self.root.total = sum(c.total for c in self.root.children.values())
        lines: list[str] = []
        total = self.root.total or 1e-9
        self._render(self.root, 0, total, lines, is_root=True)
        return "\n".join(lines)

    def _render(self, node: _Node, depth: int, grand_total: float, lines: list, is_root: bool = False) -> None:
        if not is_root:
            indent = "  " * (depth - 1)
            pct = 100.0 * node.total / grand_total
            child_sum = sum(c.total for c in node.children.values())
            self_t = node.total - child_sum
            count = f" x{node.count}" if node.count > 1 else ""
            self_str = f"  (self {self_t:5.2f}s)" if node.children else ""
            lines.append(f"{indent}{node.label:<22}{node.total:7.2f}s  {pct:5.1f}%{count}{self_str}")
            for name, value, unit in node.metrics:
                vstr = f"{value:.4g}" if isinstance(value, float) else str(value)
                lines.append(f"{indent}  . {name}: {vstr}{unit}")
        else:
            lines.append(f"{'stage':<22}{'time':>7}  {'%':>6}")
            lines.append("-" * 46)
        for child in node.children.values():
            self._render(child, depth + 1, grand_total, lines)
        if is_root:
            lines.append("-" * 46)
            lines.append(f"{'total':<22}{node.total:7.2f}s")


class _NullSpan:
    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class NullProfiler(Profiler):
    """No-op profiler for when profiling/verbose output isn't wanted."""

    def __init__(self):
        super().__init__(enabled=False)

    @contextmanager
    def span(self, label: str):
        yield None

    def metric(self, name: str, value, unit: str = "") -> None:
        pass

    def report(self) -> str:
        return ""
