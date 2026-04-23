from __future__ import annotations

from typing import Optional


class BaseState:
    def enter(self) -> None:
        pass

    def exit(self) -> None:
        pass

    def update(self, dt: float) -> None:
        pass

    def render(self, surface) -> None:
        pass

    def handle_input(self, events) -> None:
        pass


class GameStateManager:
    def __init__(self) -> None:
        self.current_state: Optional[BaseState] = None

    def set_state(self, new_state: BaseState) -> None:
        if self.current_state is not None:
            self.current_state.exit()
        self.current_state = new_state
        self.current_state.enter()

    def handle_input(self, events) -> None:
        if self.current_state:
            self.current_state.handle_input(events)

    def update(self, dt: float) -> None:
        if self.current_state:
            self.current_state.update(dt)

    def render(self, surface) -> None:
        if self.current_state:
            self.current_state.render(surface)
