from __future__ import annotations

from collections import deque
import random
import pygame


class Player:
    def __init__(self, x: float, y: float) -> None:
        self.pos = pygame.Vector2(x, y)
        self.vel = pygame.Vector2(0, 0)
        self.accel = 900.0
        self.max_speed = 120.0
        self.friction = 1100.0
        self.rect = pygame.Rect(x, y, 12, 14)
        self.stress = 0.0
        self.input_delay_queue = deque(maxlen=4)

    def set_stress(self, value: float) -> None:
        self.stress = max(0.0, min(1.0, value))

    def _read_input(self) -> pygame.Vector2:
        keys = pygame.key.get_pressed()
        raw = pygame.Vector2(
            (1 if keys[pygame.K_d] or keys[pygame.K_RIGHT] else 0)
            - (1 if keys[pygame.K_a] or keys[pygame.K_LEFT] else 0),
            (1 if keys[pygame.K_s] or keys[pygame.K_DOWN] else 0)
            - (1 if keys[pygame.K_w] or keys[pygame.K_UP] else 0),
        )
        if raw.length_squared() > 1:
            raw = raw.normalize()

        self.input_delay_queue.append(raw)
        delay_frames = 1 + int(self.stress * 2)
        if len(self.input_delay_queue) > delay_frames:
            delayed = self.input_delay_queue[0]
        else:
            delayed = raw
        instability = pygame.Vector2(random.uniform(-1, 1), random.uniform(-1, 1)) * (self.stress * 0.11)
        return delayed + instability

    def update(self, dt: float, tilemap) -> None:
        direction = self._read_input()
        if direction.length_squared() > 0:
            if direction.length_squared() > 1:
                direction = direction.normalize()
            self.vel += direction * self.accel * dt
        else:
            speed = self.vel.length()
            if speed > 0:
                drop = min(speed, self.friction * dt)
                self.vel.scale_to_length(max(0, speed - drop)) if speed - drop > 0 else self.vel.update(0, 0)

        if self.vel.length() > self.max_speed:
            self.vel.scale_to_length(self.max_speed)

        self._move_with_collision(dt, tilemap)

    def _move_with_collision(self, dt: float, tilemap) -> None:
        self.pos.x += self.vel.x * dt
        self.rect.topleft = (round(self.pos.x), round(self.pos.y))
        if self._colliding(tilemap):
            self.pos.x -= self.vel.x * dt
            self.vel.x *= -0.2

        self.pos.y += self.vel.y * dt
        self.rect.topleft = (round(self.pos.x), round(self.pos.y))
        if self._colliding(tilemap):
            self.pos.y -= self.vel.y * dt
            self.vel.y *= -0.2

        self.rect.topleft = (round(self.pos.x), round(self.pos.y))

    def _colliding(self, tilemap) -> bool:
        for p in (self.rect.topleft, self.rect.topright, self.rect.bottomleft, self.rect.bottomright):
            if tilemap.is_blocked(p[0], p[1]):
                return True
        return False

    def render(self, surface: pygame.Surface, camera) -> None:
        draw_rect = camera.apply_rect(self.rect)
        pygame.draw.rect(surface, (190, 205, 220), draw_rect)
