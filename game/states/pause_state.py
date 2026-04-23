from __future__ import annotations

import pygame


class PauseState:
    def __init__(self, game, previous_state) -> None:
        self.game = game
        self.previous_state = previous_state

    def enter(self) -> None:
        pass

    def exit(self) -> None:
        pass

    def handle_input(self, events) -> None:
        for event in events:
            if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                self.game.state_manager.set_state(self.previous_state)

    def update(self, dt: float) -> None:
        _ = dt

    def render(self, surface) -> None:
        self.previous_state.render(surface)
        shade = pygame.Surface(surface.get_size(), pygame.SRCALPHA)
        shade.fill((0, 0, 0, 170))
        surface.blit(shade, (0, 0))
        self.game.text_renderer.draw(surface, "PAUSED - ESC to return", (70, 82))
