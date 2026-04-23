from __future__ import annotations

import pygame

from game.entities.interactable import Interactable
from game.states.memory_state import MemoryState
from game.states.pause_state import PauseState
from game.systems.interaction_system import InteractionSystem


class ExplorationState:
    def __init__(self, game) -> None:
        self.game = game
        self.interaction_system: InteractionSystem | None = None

    def enter(self) -> None:
        interactables = []
        for entry in self.game.current_zone_data.get("interactables", []):
            interactables.append(
                Interactable(
                    entry["id"],
                    pygame.Rect(entry["rect"][0], entry["rect"][1], entry["rect"][2], entry["rect"][3]),
                    entry["prompt"],
                    entry["action"],
                )
            )
        self.interaction_system = InteractionSystem(interactables)

    def exit(self) -> None:
        pass

    def handle_input(self, events) -> None:
        for event in events:
            if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                self.game.state_manager.set_state(PauseState(self.game, self))
            if event.type == pygame.KEYDOWN and event.key == pygame.K_e and self.interaction_system:
                action = self.interaction_system.interact()
                if action:
                    self._resolve_action(action)

    def _resolve_action(self, action: dict) -> None:
        kind = action.get("type")
        if kind == "lore":
            entry_id = action["entry_id"]
            if self.game.lore_manager.unlock(entry_id):
                self.game.overlay.show_message(f"Recovered file: {entry_id}")
                self.game.event_system.emit("lore_unlocked", {"entry_id": entry_id})
        elif kind == "memory":
            self.game.state_manager.set_state(MemoryState(self.game, self.game.current_zone))
        elif kind == "zone":
            self.game.load_zone(action["zone"])
            self.game.state_manager.set_state(self.game.exploration_state)

    def update(self, dt: float) -> None:
        self.game.player.set_stress(min(1.0, self.game.lore_manager.discovered_count() / 10))
        self.game.player.update(dt, self.game.tilemap)
        self.game.camera.update(self.game.player.rect, dt)
        if self.interaction_system:
            self.interaction_system.update(self.game.player.rect)
            if self.interaction_system.nearby:
                self.game.overlay.show_message(self.interaction_system.nearby.prompt, 0.12)
        self.game.overlay.update(dt)

        trigger = self.game.tilemap.query_trigger(self.game.player.rect.centerx, self.game.player.rect.centery)
        if trigger == 1 and not self.game.lore_manager.has_flag("flicker_seen"):
            self.game.lore_manager.set_flag("flicker_seen")
            self.game.event_system.emit("flicker")

    def render(self, surface) -> None:
        self.game.tilemap.render(surface, self.game.camera, "visual")
        if self.interaction_system:
            for interactable in self.interaction_system.interactables:
                interactable.render_hint(surface, self.game.camera)
        self.game.player.render(surface, self.game.camera)
        self.game.lighting.render(surface, self.game.camera.apply_rect(self.game.player.rect).center)
        self.game.overlay.render(surface)
