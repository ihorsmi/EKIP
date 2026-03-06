from __future__ import annotations

from dataclasses import dataclass
from typing import List


@dataclass(frozen=True)
class Chunk:
    index: int
    text: str


def chunk_text(text: str, *, chunk_size: int = 1200, overlap: int = 200) -> List[Chunk]:
    """Simple character-based chunker for ingestion."""
    cleaned = " ".join(text.replace("\u0000", " ").split())
    if not cleaned:
        return []

    chunks: List[Chunk] = []
    start = 0
    idx = 0
    while start < len(cleaned):
        end = min(start + chunk_size, len(cleaned))
        chunk = cleaned[start:end].strip()
        if chunk:
            chunks.append(Chunk(index=idx, text=chunk))
            idx += 1
        if end == len(cleaned):
            break
        start = max(0, end - overlap)
    return chunks

