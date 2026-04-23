from __future__ import annotations

import pygame

from game.core import config
from game.core.state_manager import GameStateManager
from game.entities.player import Player
from game.states.exploration_state import ExplorationState
from game.systems.audio_system import AudioSystem
from game.systems.event_system import EventSystem
from game.systems.lighting import LightingSystem
from game.systems.lore_manager import LoreManager
from game.systems.vhs_effect import VHSEffect
from game.ui.overlay import OverlayUI
from game.ui.text_renderer import TextRenderer
from game.world.camera import Camera
from game.world.level_loader import LevelLoader


class Game:
    def __init__(self) -> None:
        pygame.init()
        self.screen = pygame.display.set_mode((config.SCREEN_WIDTH, config.SCREEN_HEIGHT))
        self.internal_surface = pygame.Surface((config.INTERNAL_WIDTH, config.INTERNAL_HEIGHT))
        pygame.display.set_caption(config.TITLE)
        self.clock = pygame.time.Clock()
        self.running = True

        self.state_manager = GameStateManager()
        self.text_renderer = TextRenderer()
        self.overlay = OverlayUI(self.text_renderer)

        self.audio = AudioSystem()
        self.event_system = EventSystem()
        self.lore_manager = LoreManager(config.LORE_PATH)
        self.level_loader = LevelLoader(config.LEVEL_PATH)

        self.camera = Camera(config.INTERNAL_WIDTH, config.INTERNAL_HEIGHT)
        self.lighting = LightingSystem(config.INTERNAL_WIDTH, config.INTERNAL_HEIGHT)
        self.vhs = VHSEffect(config.INTERNAL_WIDTH, config.INTERNAL_HEIGHT)

        self.current_zone = "entrance_lobby"
        self.current_zone_data = {}
        self.tilemap = None
        self.player = Player(0, 0)

        self._bind_events()
        self.load_zone(self.current_zone)
        self.exploration_state = ExplorationState(self)
        self.state_manager.set_state(self.exploration_state)

    def _bind_events(self) -> None:
        self.event_system.on("lore_unlocked", self._on_lore_unlocked)
        self.event_system.on("flicker", self._on_flicker)

    def _on_lore_unlocked(self, payload: dict) -> None:
        _ = payload
        discovered = self.lore_manager.discovered_count()
        if discovered >= 3:
            self.lighting.set_profile(210, 72)
            self.audio.set_ambience("noise")
        if discovered >= 6:
            self.level_loader.data["zones"]["back_hallways"]["locked"] = False

    def _on_flicker(self, payload: dict) -> None:
        _ = payload
        self.lighting.set_profile(230, 60)
        self.overlay.show_message("Lights desync for a brief moment.", 1.8)

    def load_zone(self, zone_name: str) -> None:
        self.current_zone = zone_name
        self.current_zone_data = self.level_loader.get_zone(zone_name)
        self.tilemap = self.level_loader.load_tilemap(zone_name)
        spawn_x, spawn_y = self.level_loader.get_spawn(zone_name)
        self.player.pos.update(spawn_x, spawn_y)
        self.player.rect.topleft = (int(spawn_x), int(spawn_y))

    def run(self) -> None:
        while self.running:
            dt = self.clock.tick(config.TARGET_FPS) / 1000.0
            events = pygame.event.get()
            for event in events:
                if event.type == pygame.QUIT:
                    self.running = False

            self.state_manager.handle_input(events)
            self.state_manager.update(dt)
            self.event_system.update()
            self.audio.update(dt)

            self.internal_surface.fill((14, 14, 18))
            self.state_manager.render(self.internal_surface)
            self.vhs.apply(self.internal_surface)

            scaled = pygame.transform.scale(self.internal_surface, self.screen.get_size())
            self.screen.blit(scaled, (0, 0))
            pygame.display.flip()

        pygame.quit()
