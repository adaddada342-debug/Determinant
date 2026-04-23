from __future__ import annotations


class OverlayUI:
    def __init__(self, text_renderer) -> None:
        self.text_renderer = text_renderer
        self.message = ""
        self.timer = 0.0
        self.typewriter_idx = 0.0

    def show_message(self, message: str, duration: float = 2.8) -> None:
        self.message = message
        self.timer = duration
        self.typewriter_idx = 0.0

    def update(self, dt: float) -> None:
        if self.timer > 0:
            self.timer -= dt
            self.typewriter_idx += dt * 28

    def render(self, surface) -> None:
        if self.timer <= 0 or not self.message:
            return
        chars = int(self.typewriter_idx)
        visible = self.message[:chars]
        fade = max(0, min(255, int((self.timer / 2.8) * 255)))
        self.text_renderer.draw(surface, visible, (8, surface.get_height() - 18), alpha=fade)
