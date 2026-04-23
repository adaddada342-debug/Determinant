from __future__ import annotations


class EventSystem:
    def __init__(self) -> None:
        self.queue: list[dict] = []
        self.listeners: dict[str, list] = {}

    def on(self, event_name: str, callback) -> None:
        self.listeners.setdefault(event_name, []).append(callback)

    def emit(self, event_name: str, payload: dict | None = None) -> None:
        self.queue.append({"name": event_name, "payload": payload or {}})

    def update(self) -> None:
        while self.queue:
            event = self.queue.pop(0)
            for callback in self.listeners.get(event["name"], []):
                callback(event["payload"])
