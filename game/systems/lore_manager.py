from __future__ import annotations

import json
from pathlib import Path


class LoreManager:
    def __init__(self, lore_file: Path) -> None:
        self.data = json.loads(lore_file.read_text(encoding="utf-8"))
        self.discovered: set[str] = set()
        self.flags: set[str] = set()

    def unlock(self, entry_id: str) -> bool:
        if entry_id in self.discovered:
            return False
        self.discovered.add(entry_id)
        for category in self.data.values():
            for row in category:
                if row["id"] == entry_id:
                    row["unlocked"] = True
                    return True
        return False

    def discovered_count(self) -> int:
        return len(self.discovered)

    def get_unlocked_entries(self) -> list[dict]:
        out = []
        for category, rows in self.data.items():
            for row in rows:
                if row["unlocked"]:
                    out.append({"category": category, **row})
        return out

    def has_flag(self, flag: str) -> bool:
        return flag in self.flags

    def set_flag(self, flag: str) -> None:
        self.flags.add(flag)
