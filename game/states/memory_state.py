from __future__ import annotations

import pygame


class MemoryState:
    def __init__(self, game, origin_zone: str) -> None:
        self.game = game
        self.origin_zone = origin_zone
        self.timer = 0.0
        self.duration = 9.0

    def enter(self) -> None:
        self.game.overlay.show_message("Memory fragment: hallway repetition detected.", 3.2)

    def exit(self) -> None:
        pass

    def handle_input(self, events) -> None:
        for event in events:
            if event.type == pygame.KEYDOWN and event.key == pygame.K_e:
                self.timer = self.duration

    def update(self, dt: float) -> None:
        self.timer += dt
        self.game.overlay.update(dt)
        if self.timer >= self.duration:
            self.game.load_zone(self.origin_zone)
            self.game.state_manager.set_state(self.game.exploration_state)

    def render(self, surface) -> None:
        surface.fill((23, 18, 20))
        loop_offset = int(self.timer * 30) % 40
        for i in range(0, surface.get_width(), 40):
            pygame.draw.rect(surface, (64, 52, 58), pygame.Rect(i - loop_offset, 42, 18, 96))
        self.game.overlay.render(surface)
