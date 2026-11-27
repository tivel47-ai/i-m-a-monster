# Манифест игровых звуков

## Главное меню

Игровые файлы находятся в `assets/audio/local/`. Музыка использует Ogg Vorbis в стерео при 48 кГц. Проигрыватель запускает темы по очереди с перекрёстным затуханием за 5 с до конца каждой записи. Клик использует один монофонический WAV с исходным PCM 24 бит / 48 кГц. Godot импортирует его как PCM16 без сжатия.

| Игровой файл | Тема или действие | Длительность | Канал |
|---|---|---:|---|
| `music/menu_theme_a_the_sleeping_evil.ogg` | The Sleeping Evil, 56 BPM | 205,714 с | Music |
| `music/menu_theme_b_the_last_prayer.ogg` | The Last Prayer, 60 BPM | 192,000 с | Music |
| `music/menu_theme_c_the_ancient_hunger.ogg` | The Ancient Hunger, 50 BPM | 211,200 с | Music |
| `ui/ui_click_soft.wav` | Нажатие основных кнопок меню | 0,162 с | UI |

В игровых файлах измерена интегральная громкость A/B/C −19,1/−19,0/−19,1 LUFS и истинные пики −5,0/−4,4/−3,7 dBTP. Истинный пик клика −18,2 dBTP. Замеры сделаны до регулировки шинами.

[Происхождение](../assets/audio/PROVENANCE.md#главное-меню) · [Уведомления об условиях CC0 и CC BY](../assets/audio/THIRD_PARTY_NOTICES.md#главное-меню)

## Audio Prototype Pack #1 — Living Village

**Источник и права для всех 46 строк.** Living Village собран из сторонних записей. Аудит 27.11.2026 подтвердил разрешение CC0 на коммерческое использование, переработку и публичное распространение. Авторы, ссылки, обработка, контрольные суммы и границы проверки приведены в [реестре происхождения](../assets/audio/PROVENANCE.md) и [уведомлениях](../assets/audio/THIRD_PARTY_NOTICES.md). Входная папка `assets/audio/_incoming/pack_01/` исключена из Git. Проверенные игровые WAV из `assets/audio/local/` и их настройки импорта включены в список разрешённых путей. Отдельную существующую запись колокола необходимо проверить перед публичным распространением.

**Имена и формат.** Имя исходника для каждой строки совпадает с каноническим ID и расширением `.wav`. Путь игрового файла указан относительно `assets/audio/local/`. Все файлы — WAV PCM16, 48 кГц. Каналы указаны в таблице. Игровые WAV побайтово совпадают с исходниками. Сравнение хешей декодированных PCM не выявило точных дубликатов.

**Замеры.** Пик измерен в dBFS. Клиппинг — число отсчётов на уровне ±32767 и выше по модулю. Начало и хвост — время ниже порога приблизительно −50 dBFS, а не результат прослушивания. Для петель проверена метка `smpl`. Столбец «Стык» показывает максимальную разность крайних отсчётов PCM16 между каналами. Слышимость стыков и точность классификации на слух предстоит проверить в игре. У шагов и попаданий используют небольшой сдвиг старта, заданный в реестре. Остальные записи запускаются с начала.

| ID записи | Категория / событие | Игровой файл | Сек. | Кан. | Петля | Пик | Клип. | Начало / хвост, с | Стык | Статус |
|---|---|---|---:|---:|---|---:|---:|---:|---:|---|
| `amb_wind_base_01` | `ambience.wind.base` | `ambience/global/amb_wind_base_01.wav` | 30.00 | 2 | да | -15.00 | 0 | 0.000 / 0.000 | 0 | подключён в Миссии №1 |
| `amb_village_distant_01` | `ambience.village.distant` | `ambience/global/amb_village_distant_01.wav` | 30.00 | 2 | да | -25.00 | 0 | 0.003 / 0.003 | 0 | подключён в Миссии №1 |
| `amb_river_01` | `ambience.river.flow` | `ambience/nature/amb_river_01.wav` | 30.00 | 1 | да | -16.35 | 0 | 0.000 / 0.000 | 0 | подключён в Миссии №1 |
| `amb_forest_01` | `ambience.forest.vegetation` | `ambience/nature/amb_forest_01.wav` | 30.00 | 2 | да | -23.47 | 0 | 0.000 / 0.000 | 0 | подключён в Миссии №1 |
| `amb_dark_drone_01` | `ambience.tension.dark` | `ambience/global/amb_dark_drone_01.wav` | 30.00 | 2 | да | -27.36 | 0 | 0.005 / 0.001 | 0 | подключён в Миссии №1 |
| `env_crow_01` | `environment.animal.crow` | `environment/animals/env_crow_01.wav` | 3.40 | 1 | — | -13.00 | 0 | 0.369 / 1.115 | — | подключён в Миссии №1 |
| `env_crow_02` | `environment.animal.crow` | `environment/animals/env_crow_02.wav` | 3.20 | 1 | — | -13.00 | 0 | 0.223 / 1.045 | — | подключён в Миссии №1 |
| `env_crow_03` | `environment.animal.crow` | `environment/animals/env_crow_03.wav` | 3.80 | 1 | — | -14.00 | 0 | 0.438 / 2.020 | — | подключён в Миссии №1 |
| `env_birds_01` | `environment.animal.birds` | `environment/animals/env_birds_01.wav` | 6.20 | 1 | — | -17.00 | 0 | 0.434 / 1.792 | — | подключён в Миссии №1 |
| `env_birds_02` | `environment.animal.birds` | `environment/animals/env_birds_02.wav` | 6.00 | 1 | — | -17.50 | 0 | 0.385 / 0.847 | — | подключён в Миссии №1 |
| `env_birds_03` | `environment.animal.birds` | `environment/animals/env_birds_03.wav` | 6.80 | 1 | — | -18.00 | 0 | 0.584 / 1.848 | — | подключён в Миссии №1 |
| `env_dog_bark_01` | `environment.animal.dog` | `environment/animals/env_dog_bark_01.wav` | 3.80 | 1 | — | -11.60 | 0 | 0.681 / 2.506 | — | резерв |
| `env_dog_bark_02` | `environment.animal.dog` | `environment/animals/env_dog_bark_02.wav` | 3.55 | 1 | — | -11.50 | 0 | 0.428 / 1.333 | — | резерв |
| `env_dog_bark_03` | `environment.animal.dog` | `environment/animals/env_dog_bark_03.wav` | 4.15 | 1 | — | -11.80 | 0 | 0.566 / 2.067 | — | резерв |
| `env_fire_loop_01` | `environment.fire.loop` | `environment/buildings/env_fire_loop_01.wav` | 30.00 | 1 | да | -16.00 | 0 | 0.000 / 0.003 | 0 | подключён в Миссии №1 |
| `human_chatter_01` | `human.civilian.chatter` | `units/humans/civilians/human_chatter_01.wav` | 6.80 | 1 | — | -13.00 | 0 | 0.372 / 0.759 | — | подключён в Миссии №1 |
| `human_chatter_02` | `human.civilian.chatter` | `units/humans/civilians/human_chatter_02.wav` | 5.95 | 1 | — | -13.00 | 0 | 0.366 / 0.678 | — | подключён в Миссии №1 |
| `human_chatter_03` | `human.civilian.chatter` | `units/humans/civilians/human_chatter_03.wav` | 6.55 | 1 | — | -13.00 | 0 | 0.272 / 1.392 | — | подключён в Миссии №1 |
| `human_chatter_04` | `human.civilian.chatter` | `units/humans/civilians/human_chatter_04.wav` | 7.30 | 1 | — | -13.00 | 0 | 0.485 / 0.964 | — | подключён в Миссии №1 |
| `human_fear_01` | `human.civilian.fear` | `units/humans/civilians/human_fear_01.wav` | 1.35 | 1 | — | -9.58 | 0 | 0.112 / 0.595 | — | подключён в Миссии №1 |
| `human_fear_02` | `human.civilian.fear` | `units/humans/civilians/human_fear_02.wav` | 1.25 | 1 | — | -10.00 | 0 | 0.074 / 0.750 | — | подключён в Миссии №1 |
| `human_fear_03` | `human.civilian.fear` | `units/humans/civilians/human_fear_03.wav` | 1.50 | 1 | — | -10.00 | 0 | 0.098 / 1.047 | — | подключён в Миссии №1 |
| `human_fear_04` | `human.civilian.fear` | `units/humans/civilians/human_fear_04.wav` | 1.15 | 1 | — | -10.00 | 0 | 0.080 / 0.736 | — | подключён в Миссии №1 |
| `human_fear_05` | `human.civilian.fear` | `units/humans/civilians/human_fear_05.wav` | 1.70 | 1 | — | -10.00 | 0 | 0.094 / 1.173 | — | подключён в Миссии №1 |
| `footstep_dirt_light_01` | `movement.footstep.dirt.light` | `environment/footsteps/footstep_dirt_light_01.wav` | 0.66 | 1 | — | -11.00 | 0 | 0.086 / 0.291 | — | подключён в Миссии №1 |
| `footstep_dirt_light_02` | `movement.footstep.dirt.light` | `environment/footsteps/footstep_dirt_light_02.wav` | 0.60 | 1 | — | -11.00 | 0 | 0.083 / 0.160 | — | подключён в Миссии №1 |
| `footstep_dirt_light_03` | `movement.footstep.dirt.light` | `environment/footsteps/footstep_dirt_light_03.wav` | 0.68 | 1 | — | -11.00 | 0 | 0.058 / 0.218 | — | подключён в Миссии №1 |
| `footstep_dirt_light_04` | `movement.footstep.dirt.light` | `environment/footsteps/footstep_dirt_light_04.wav` | 0.64 | 1 | — | -11.00 | 0 | 0.088 / 0.242 | — | подключён в Миссии №1 |
| `footstep_dirt_light_05` | `movement.footstep.dirt.light` | `environment/footsteps/footstep_dirt_light_05.wav` | 0.57 | 1 | — | -11.00 | 0 | 0.072 / 0.204 | — | подключён в Миссии №1 |
| `footstep_dirt_light_06` | `movement.footstep.dirt.light` | `environment/footsteps/footstep_dirt_light_06.wav` | 0.65 | 1 | — | -11.00 | 0 | 0.102 / 0.243 | — | подключён в Миссии №1 |
| `zombie_ordinary_idle_01` | `zombie.ordinary.idle` | `units/zombies/ordinary/zombie_ordinary_idle_01.wav` | 2.00 | 1 | — | -13.82 | 0 | 0.104 / 0.215 | — | подключён в Миссии №1 |
| `zombie_ordinary_idle_02` | `zombie.ordinary.idle` | `units/zombies/ordinary/zombie_ordinary_idle_02.wav` | 2.00 | 1 | — | -10.77 | 0 | 0.117 / 0.579 | — | подключён в Миссии №1 |
| `zombie_ordinary_idle_03` | `zombie.ordinary.idle` | `units/zombies/ordinary/zombie_ordinary_idle_03.wav` | 2.00 | 1 | — | -14.23 | 0 | 0.120 / 0.214 | — | подключён в Миссии №1 |
| `zombie_ordinary_idle_04` | `zombie.ordinary.idle` | `units/zombies/ordinary/zombie_ordinary_idle_04.wav` | 2.00 | 1 | — | -11.84 | 0 | 0.121 / 0.820 | — | подключён в Миссии №1 |
| `zombie_ordinary_idle_05` | `zombie.ordinary.idle` | `units/zombies/ordinary/zombie_ordinary_idle_05.wav` | 2.00 | 1 | — | -11.66 | 0 | 0.106 / 0.500 | — | подключён в Миссии №1 |
| `zombie_ordinary_attack_01` | `zombie.ordinary.attack` | `units/zombies/ordinary/zombie_ordinary_attack_01.wav` | 1.05 | 1 | — | -8.00 | 0 | 0.124 / 0.313 | — | подключён в Миссии №1 |
| `zombie_ordinary_attack_02` | `zombie.ordinary.attack` | `units/zombies/ordinary/zombie_ordinary_attack_02.wav` | 1.10 | 1 | — | -9.00 | 0 | 0.102 / 0.298 | — | подключён в Миссии №1 |
| `zombie_ordinary_attack_03` | `zombie.ordinary.attack` | `units/zombies/ordinary/zombie_ordinary_attack_03.wav` | 1.20 | 1 | — | -9.00 | 0 | 0.122 / 0.337 | — | подключён в Миссии №1 |
| `zombie_ordinary_attack_04` | `zombie.ordinary.attack` | `units/zombies/ordinary/zombie_ordinary_attack_04.wav` | 1.28 | 1 | — | -9.00 | 0 | 0.126 / 0.299 | — | подключён в Миссии №1 |
| `zombie_ordinary_attack_05` | `zombie.ordinary.attack` | `units/zombies/ordinary/zombie_ordinary_attack_05.wav` | 1.15 | 1 | — | -9.00 | 0 | 0.102 / 0.230 | — | подключён в Миссии №1 |
| `combat_flesh_impact_01` | `combat.impact.flesh` | `combat/impacts/combat_flesh_impact_01.wav` | 0.67 | 1 | — | -9.00 | 0 | 0.048 / 0.326 | — | подключён в Миссии №1 |
| `combat_flesh_impact_02` | `combat.impact.flesh` | `combat/impacts/combat_flesh_impact_02.wav` | 0.71 | 1 | — | -9.00 | 0 | 0.137 / 0.230 | — | подключён в Миссии №1 |
| `combat_flesh_impact_03` | `combat.impact.flesh` | `combat/impacts/combat_flesh_impact_03.wav` | 0.77 | 1 | — | -9.16 | 0 | 0.047 / 0.337 | — | подключён в Миссии №1 |
| `combat_flesh_impact_04` | `combat.impact.flesh` | `combat/impacts/combat_flesh_impact_04.wav` | 0.63 | 1 | — | -9.13 | 0 | 0.130 / 0.219 | — | подключён в Миссии №1 |
| `combat_flesh_impact_05` | `combat.impact.flesh` | `combat/impacts/combat_flesh_impact_05.wav` | 0.75 | 1 | — | -9.00 | 0 | 0.100 / 0.329 | — | подключён в Миссии №1 |
| `combat_flesh_impact_06` | `combat.impact.flesh` | `combat/impacts/combat_flesh_impact_06.wav` | 0.64 | 1 | — | -10.68 | 0 | 0.122 / 0.178 | — | подключён в Миссии №1 |
