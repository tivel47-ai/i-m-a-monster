# Guard AI — canonical confirmed design

**Decision record:** 2026-11-04. **Implementation update:** 2026-11-04. Confirmed rules remain authoritative; current integration and validation are recorded in §13 and §18.

This is the authoritative specification for the confirmed guard behavior of **I'm a Monster**. It preserves the user's design decisions for future implementation. Where older design descriptions conflict, this specification controls the intended guard behavior; older implementation reports remain records of what the prototype actually does.

## 1. Status, context, and decision index

**CONFIRMED DESIGN** means approved behavior, not a working feature. **CURRENT IMPLEMENTATION** means source inspected in this repository on 2026-11-04. **NOT YET IMPLEMENTED** means a confirmed requirement is absent from that inspected architecture. **DEFERRED** means details remain undecided. **PROPOSED** means an unapproved suggestion; this document introduces no proposed gameplay decisions. Implementation structure may be hierarchical or compositional provided it preserves these semantics.

The game is a 2D top-down pixel-art tactical strategy in a medieval dark-fantasy village, simulated in real time with tactical pause. The player gives high-level monster orders rather than directly moving individual characters. Zombies are the only playable monster race in the first prototype. Monsters, guards, and civilians act autonomously; combat outcomes arise from individual real-time interactions, not an abstract comparison of total army power.

The first large village has approximately 30 inhabitants: 19 peasants, 5 artisans, 5 guards, and 1 priest. It contains homes, work areas, roads, gathering sites, a church/chapel, guard-post facilities, and an alarm bell. Preserve the existing five-guard, three-route patrol foundation and post/shift behavior. The small test map is a separate fixture, not a replacement for this population or patrol setup.

| Decision/status checklist | Status | Specification / implementation evidence |
|---|---|---|
| Local knowledge and ordinary LOS/reaction foundations | Confirmed; perception foundation implemented | §2; §13 |
| B2 — Reasonable Defender, contextual combat/retreat/pursuit | Confirmed; prototype integrated, numerical combat balance deferred | §2, §4 |
| Four alert levels, physical bell activation | Confirmed; physical bell integrated; defense trigger approved, implementation pending | §3, §13 |
| Nine conceptual guard states, separate behavioral dimensions | Confirmed; integrated in GuardAI | §5 |
| Bounded relevant tasks, interruption and contextual priorities | Confirmed; prototype integrated | §6 |
| Existing peaceful routes and post relief | Confirmed foundation; implemented | §3, §13 |
| ALARM territorial patrol and active civilian recruitment | Confirmed; prototype integrated | §3, §8 |
| Civilian equipment, 60% arming, role-weighted weapons | Confirmed; prototype integrated | §9 |
| Individual follower behavior, cohesion and recovery | Confirmed; prototype integrated | §8, §10 |
| Provenance, one retransmission, assistance and local acknowledgements | Confirmed; guard relay protocol integrated; civilian legacy delivery retained | §7, §13 |
| Peer patrol cooperation and genuinely agreed dynamic waypoints | Confirmed; prototype integrated | §11 |
| Priest influence / non-combat boundary | Confirmed high-level boundary; morale/command details deferred | §12 |
| ORGANIZED_DEFENSE general level and civilian arming | Confirmed trigger and arming intent; detailed mobilization deferred | §3, §9, §14 |
| Автоматическое затухание глобальной тревоги | Отключено по утверждённому дизайну MVP | §3 |
| Точная настройка, вместимость очереди задач и числовой баланс | Отложены | §14 |
| Proposed alternatives | None approved or added by this record | Do not treat future proposals as confirmed |

**Navigation:** overview [GDD](game_design.md); source architecture and historical validation [TDD](technical_design.md); implemented large village [village simulation](village_simulation.md). The acceptance matrix is §15; the prompt coverage audit is §16; the change log is §17.

## 2. Foundational AI principles — CONFIRMED DESIGN

### 2.1 Local knowledge

A guard acts on personal observation, physically/audibly received reports, and plausible inference. There is no omniscient shared enemy tracker. Guards do not automatically know every zombie's position, distant combat outcomes, a lost target's current location, another guard's decisions, or the incident location merely because the village bell rang. Reports may be old, incomplete, uncertain, or inaccurate. Remembering a reference to an actor must not grant continuing access to hidden coordinates.

General villager perception uses approximately 360-degree detection, line-of-sight checks, reaction delay, and variation in recognition/reaction. Buildings and obstacles block vision. Guards retain these foundations while applying their own tactical reasoning. A bell conveys danger awareness, not personal visual recognition or exact monster positions.

### 2.2 B2 — Reasonable Defender

Guards neither blindly attack every enemy nor automatically flee every dangerous encounter. They continually assess available evidence, known nearby allies, their own condition, tactical position, apparent threat scale, accessibility, and consequences. This model applies during investigation, combat, retreat, alarm attempts, assistance, and temporary group coordination.

Evaluate individual actors, weapons, positions, terrain, knowledge, and real interactions. Do not replace these decisions or combat outcomes with one rigid global army-strength number. This specification supplies no numeric combat balance or universal engagement threshold.

## 3. Village alert and patrol interaction — CONFIRMED DESIGN

Village alert is separate from any guard's state, task, group, or local knowledge.

| Village level | Meaning | Guard patrol response |
|---|---|---|
| `NORMAL` | Ordinary village life | Established patrol routes and guard-post/shift duties |
| `SUSPICION` | Первое личное обнаружение монстра или тела жителя стражником либо принятый им достоверный местный доклад | Intensified patrol, generally keeping familiar routes and territorial responsibilities; investigate, search, fight, or warn locally as justified |
| `ALARM` | Успешное физическое взаимодействие с колоколом | Defensive, flexible territorial patrol; adjust local routes to known incidents and accessible paths; watch civilians/nearby guards, recruit suitable companions, and cooperate temporarily when justified |
| `ORGANIZED_DEFENSE` | Немедленный переход при достижении порога отдельной шкалы после колокола | Физическая мобилизация с вооружением по §9. Командование, патруль и координация требуют дальнейшего дизайна |

**Physical notification is mandatory:** incident scores, repeated sightings, accumulated reports, or information alone must not remotely or automatically activate village-wide ALARM. Подходящий NPC должен физически добраться до колокола и завершить взаимодействие. The bell can be inaccessible, the attempt interrupted, or the warning too late. ALARM does not automatically constitute ORGANIZED_DEFENSE.

Guards and the priest have priority for raising a credible alarm. Крестьяне и ремесленники также могут попытаться поднять тревогу, в том числе по редкой ветке личного обнаружения монстра, описанной ниже. Once the bell has already been activated, a duplicate raise-alarm task is unnecessary. Any guard learning that it has sounded must reevaluate the task using plausible information; the bell still does not disclose enemy coordinates.

At ALARM, a guard keeps general responsibility for the assigned territory, rather than automatically discarding every old route. Local detours, aid, recruitment, and cooperation are contextual. Do not concentrate all five guards at one incident or permanently abandon village sectors without a real reason. Patrols return through ordinary navigation, never teleportation.

**Уточнение утверждённого дизайна от 05.11.2026.** Условия переходов определены в [GDD §8.1](game_design.md#81-утверждённый-дизайн-эскалации). При личном обнаружении или достоверном докладе стражник сразу регистрирует каждое уникальное тело и переводит деревню из `NORMAL` в `SUSPICION`. Один ограниченный поиск по доступным точкам может охватить несколько тел. Посильного противника стражник может победить по B2, затем завершает осмотр. Победа сохраняет право на проверку шанса по телу. Превосходящая угроза допускает отход и физический звон по B2 без ожидания проверки.

После завершённого осмотра и устранения непосредственной угрозы стражник оценивает до одной допустимой возможности на каждое новое тело, пока `ALARM` не активирован и задача колокола ещё не выполняется. Шанс зависит от скрытого общего числа тел. Если попытка звона не выбрана, стражник возвращается к патрулю по текущему уровню. Прерывание не завершает осмотр и не даёт повторных проверок. Регистрации сохраняются, а обработка оставшихся возможностей при смерти или переназначении остаётся деталью реализации.

B2, местная связь и память, прерывания, временные союзы, состав патрулей и обращение со спутниками действуют по остальным разделам этой спецификации. Местная победа или истечение личной задачи не понижают общий уровень. Редкое решение крестьян и ремесленников (2% при личном обнаружении живого монстра до колокола) остаётся отдельным от B2 и реакции священника. При достижении порога после звона меняется уровень. Командование и исполнение мобилизации остаются открытыми.

**Подтверждённое уточнение пользователя 04.11.2026:** после колокола подготовительный сбор спутников имеет приоритет над старым SEARCH/INVESTIGATE. Личный непосредственный бой и необходимое отступление сохраняют приоритет безопасности. Без готового спутника стражник не выбирает добровольный поиск/расследование старого следа при ALARM; после ограниченной попытки сбора продолжает защитный патруль и приглашения, а не бесконечное ожидание.

Первое личное распознавание живого монстра или обнаружение тела стражником, равно как и достоверный местный доклад стражнику об одном из этих событий, сразу включает `SUSPICION` из `NORMAL`. Передача только между гражданскими остаётся местной. Общий уровень не раскрывает координаты или чужие наблюдения. Автоматического глобального понижения в MVP нет.

## 4. Individual tactical behavior — CONFIRMED DESIGN

### 4.1 Discovery, reports, and alarm decisions

**Новое подтверждённое и реализованное уточнение 04.11.2026:** непосредственный очевидец сначала предупреждает соседей и ищет ближайшую доступную стражу. После местной встречи крестьянин/ремесленник становится спутником до колокола; стражник ведёт расследование последней известной области, по пути предпочитает помощь свободного стражника и может приглашать других жителей. Сохраняются лимит двух гражданских и равноправие временного стражника-партнёра. Посильная встреченная опасность приводит к бою; превосходящая — к отходу и физическому колоколу. Победа требует повторного обследования района перед возвратом присутствующих участников к обычной жизни. Проверенный пустой район не доказывает убийство; неудача/таймаут не дают отбоя. Уточнение отменяет обязательный предварительный ALARM для этой местной группы и прежнее безусловное S до конца миссии у успешно проверенных участников. Полный общий отбой ALARM по-прежнему не определён. Реализация и проверка — [TDD §9.16](technical_design.md#916-свидетель-стража-местное-расследование-и-возврат-к-занятиям).

On personally discovering a threat, assess apparent enemy numbers/types, known nearby allies and their locations, personal condition/ability to continue, escape routes, position/terrain, manageability, and whether support, retreat, or warning is preferable. Possible responses include engagement, holding position, cautious observation, asking for assistance, tactical retreat, and seeking the bell. Decisions are dynamic rather than automatic outcomes of one fixed threshold.

A civilian report is evidence to assess, not proof that the entire village must be alerted. When safe and appropriate, the guard receives it, retains source/location/age/reliability, travels to inspect the area, checks what is actually there, and may fight a manageable isolated threat. A serious discovery can instead lead to retreat, help, or the bell. Investigation must remain interruptible by immediate danger.

Even defeating one zombie does not automatically require ringing the bell. Consider other known incidents, evidence of wider attack, whether the local threat appears contained, remaining uncertainty, personal condition, nearby allies, and the consequences of delaying warning. Do not assume a remote outcome is known or that finishing an investigation proves the enemy dead.

### 4.2 Tactical retreat

Choose a destination dynamically from accessible navigation paths, relative safety, known allies, defensibility, obstacles, environmental danger, and the current situation. It may be near another guard, a post, a passage, or another relatively safe position. There is no rigid universal location list that always selects the same category. Unreachable destinations are invalid. Reevaluate when conditions change; retreat does not grant new information about unseen threats or allies.

### 4.3 Bounded pursuit and lost-target search

Pursue a known opponent only within reasonable distance, time, risk, and territorial limits. Never chase one zombie endlessly across the entire map. Losing contact stops live coordinate knowledge.

Remember the **last genuinely known location** and form a temporary search area around it. Dynamically choose approximately two or three useful, accessible points using terrain, navigation, obstacles and opportunities to see the area. These are not permanently preplaced search markers. Use fewer if fewer valid points exist; points behind unreachable walls or blocked paths are invalid. Inspect through ordinary movement and perception, not automatic discovery.

For the first prototype, at most one temporary search area is active per guard. Search ends when relevant accessible points are checked, its period expires, information becomes irrelevant, a higher-priority event interrupts it, or the enemy is seen again. Preserve the distinction between a completed search and an interrupted one. Reacquisition updates the genuinely known position and triggers a new tactical assessment; it is not evidence that every other threat has been resolved.

After a completed search, first reevaluate outstanding urgent tasks. With none remaining: at NORMAL return toward ordinary patrol; at SUSPICION resume intensified patrol; at ALARM continue defensive/territorial activity rather than peaceful routine. A failed or completed search is not proof of enemy elimination. Exact area dimensions and timing remain tuning decisions.

## 5. Nine conceptual guard states — CONFIRMED DESIGN

| State | Responsibility |
|---|---|
| `PATROL` | Ordinary patrol on established routes |
| `ALERT_PATROL` | Intensified or alert territorial patrol |
| `INVESTIGATE` | Inspect a reported suspicious area |
| `SEARCH` | Limited search around a lost enemy's last known location |
| `COMBAT` | Direct engagement with a known threat |
| `RETREAT` | Reach a safer position |
| `ASSIST` | Travel to or respond to an allied guard's request |
| `GROUP_PATROL` | Temporarily coordinated movement between independent guard-led patrols |
| `RAISE_ALARM` | Reach and activate the village alarm mechanism |

These are conceptual responsibilities, not a mandated flat enum or nine new scripts. A hierarchical or compositional implementation is permitted. Keep **guard AI state, village alert level, current task, civilian group membership, and temporary guard-to-guard alliance** separate.

For example, a guard may be in COMBAT while the village is at ALARM, still lead civilian companions, and remember an interrupted GROUP_PATROL task. One guard with civilian followers is not by itself GROUP_PATROL: that state specifically concerns cooperation between independent guard-led patrols. Waiting for a companion can be a movement phase and is not a mandatory tenth main state.

## 6. Task memory, priorities, and transitions — CONFIRMED DESIGN

### 6.1 Relevant bounded memory

Maintain a small bounded collection of currently relevant tasks. The earlier illustrative capacity of 3–5 is **not** a finalized limit. Tasks can include report investigation, lost-target search, assistance, reaching the bell, return to patrol, and continuation of an interrupted joint operation.

Store or conceptually represent task type/goal, incident identity, information source/credibility, last-known location/area, information age, known severity, status, and valid interruption/resumption information. Report observation time must remain distinguishable from receipt time. The exact data schema is an implementation choice, not a newly prescribed class architecture.

### 6.2 Lifecycle rules

| Event / condition | Task transition and required meaning |
|---|---|
| Relevant new objective accepted | Add as pending or activate if context justifies it; reconcile duplicates first |
| Pending task selected | Active; check knowledge, route feasibility and priorities |
| Justified higher-priority activity | Current task becomes interrupted if still relevant; retain only valid continuation context |
| Interruption ends | Reevaluate all relevant tasks; resume/select only if justified, never blindly replay an obsolete action |
| Goal achieved | Completed; record what was actually achieved, not an assumed enemy death |
| Goal unnecessary/obsolete or information too old | Cancel/remove; a bell already activated invalidates a duplicate alarm objective |
| Objective cannot be reached or carried out | Infeasible/remove from active work; do not mark the underlying threat eliminated |
| Completed, irrelevant, unnecessary, expired, or infeasible task | Remove from the relevant bounded collection as appropriate |

Task status vocabulary is pending, active, interrupted, completed, canceled, and infeasible. Finishing a search/investigation or ending cooperation is not equivalent to resolving its underlying incident. Information may become obsolete even while the remembered enemy remains alive.

### 6.3 Contextual priorities

Direct imminent danger calls for immediate self-preservation/defense decisions. Necessary engagement/retreat overrides ordinary investigation or patrol. Credible urgent assistance may outweigh routine investigation; investigation/search outweigh uneventful patrol. Patrol is the baseline when no more important task remains.

There is **no** universal ordering that always selects the bell over assistance or assistance over the bell. Compare urgency, distance, accessible routes, risk, available companions, and consequences of delay. An assistance request is not an order overriding a peer's judgment or current group obligations (§10).

Prevent oscillation between similar tasks using commitment, appropriate reevaluation rules and cooldowns, while retaining responsive emergency reactions. Exact durations and thresholds are deferred. Repeated unchanged messages do not inflate urgency, make old observations fresh, or indefinitely retain tasks (§7).

## 7. Local communication and assistance — CONFIRMED DESIGN

### 7.1 Report meaning and provenance

Communication must be local, physical or audible. A warning can convey approximate danger area, approximate known enemy count/scale, observation time, whether personally witnessed or reported, original source, original incident identity, and an assistance request if any. Precision cannot exceed what the source plausibly knows. Information may be uncertain or stale.

**One retransmission:** an eyewitness A warns guard B; B may retransmit that firsthand information once to C. C must not continue forwarding the inherited warning unless C personally reconfirms the threat. Retain original provenance, observation time and incident identity; B's delivery is not a new sighting. Personal reconfirmation provides genuinely new firsthand evidence, not permission to relabel unchanged hearsay. Prevent loops and duplicate circulation.

### 7.2 Assistance requests

Distinguish an ordinary warning from a specific urgent request for help. A guard can call while moving, fighting, or retreating; no mandatory prolonged shout animation is required.

When seeking support, prefer available guards; already prepared civilian companions may also contribute. Do not deliberately recruit random unprepared civilians straight into suicidal combat. Recipients independently judge risk and feasibility. They may engage directly, cover withdrawal, protect a flank, or decline when intervention is too dangerous. Equal guards do not issue unconditional orders to each other.

### 7.3 Reconciliation, repetition, and local coordination

Reconcile observations plausibly describing one incident with its existing incident/task, rather than generating unlimited tasks. Nearby but clearly independent incidents stay distinct; geographic proximity alone is not enough to merge them.

Repeating the same assistance request without new information must not automatically increase priority. Only material changes such as additional enemies, escalation, a changed location, or changed danger justify revised urgency. Repetition does not reset the original observation age or constitute firsthand reconfirmation.

A responding guard may locally tell nearby guards that assistance is on the way. They may use this when judging whether additional response is necessary. This acknowledgement is neither instant village-wide knowledge nor evidence the enemy has been defeated, and cannot bypass the inherited warning's retransmission limit. Guards outside communication/perception range do not automatically learn the response decision.

## 8. Civilian safety, recruitment, and follower agency — CONFIRMED DESIGN

At ALARM, peasants and artisans respond individually: some prefer home/workshop, others church or gathering areas. These are variable preferences, not mandatory destinations for every civilian. A civilian moving toward safety may be invited into a guard group upon encountering a guard.

At gathering sites without leadership, civilians generally wait for defenders rather than spontaneously forming an organized militia. Immediate danger can still cause flight or hiding.

Guards **actively recruit** by local encounter; proximity does not automatically absorb civilians. Acceptance/refusal depends on proximity, courage, temperament, perceived risk and context. A group has **one guard leader and up to two civilian followers**. An NPC belongs to at most one active patrol group.

The guard leads tactical movement and decisions, but followers navigate individually and retain survival behavior. They are not rigidly attached to the leader's position. Depending on circumstances they may support a manageable fight, act cautiously in uncertainty, protect themselves/nearby allies, retreat from serious danger, or flee independently in extreme circumstances. Combat participation is flexible, neither always aggressive nor always passive. Civilians must not pursue distant enemies as independent monster hunters.

A guard's presence increases courage/willingness to resist without removing temperament; departure or loss may reduce confidence. Neither leadership nor group membership permits magical position tracking.

**Уточнение для мест сбора 04.11.2026:** ожидание защитников включает чередование пауз и короткой ходьбы внутри доступной территории. При лично замеченной или достоверно сообщённой большой группе монстров гражданский хранит личную память опасного места и после немедленного бегства предпочитает доступный дом; ремесленник также может выбрать свою мастерскую. Повтор старого сообщения не делает сведения свежими, удалённые NPC не получают память автоматически, краткая тишина не доказывает безопасность прежнего места. Число противников, область, срок памяти и темп занятий — начальные параметры реализации, а не окончательный баланс.
## 9. Civilian equipment and adjacent combat constraints — CONFIRMED DESIGN

At ALARM, each civilian recruitment has a **60% probability of arming**, with **40% remaining unarmed companions**. This is an individual recruitment decision, not a guaranteed distribution within each two-follower group. The same recruitment must not reroll equipment every frame. Unarmed followers may still attempt limited assistance/self-defense.

At ORGANIZED_DEFENSE, all available living, non-converted peasants and artisans are intended to become armed as part of broader mobilization. They do not instantly become professional guards. Условие активации определено в §3. Место вооружения в последовательности мобилизации и командование остаются открытыми.

For the first prototype, equipment acquisition is **instant**; do not require trips to stores, houses or workshops. Random weapon selection is weighted by civilian role: peasants favor pitchforks, axes, clubs, torches and agricultural implements; artisans favor hammers, axes, clubs and profession-related tools. Simple differences in damage, attack speed and reach are allowed by the selected high-level weapon system; special effects are outside the first prototype. No values or formulas are established here.

The priest remains unarmed. Guards already have guard equipment in the intended design, with melee and eventually ranged weapon types; this is not a claim that role-specific equipment is implemented in the inspected prototype.

Accepted directional combat expectations, not numeric specifications:

- A healthy guard generally has the advantage over one ordinary zombie; multiple zombies can threaten a lone guard.
- An ordinary zombie has a slight advantage over a lone armed peasant.
- Unarmed civilians are substantially more vulnerable.
- Armed artisans are broadly comparable to armed peasants, with differences largely due to equipment.

Do not infer damage tables, HP thresholds, weapon values or combat formulas from these intentions.

## 10. Cohesion, separation, and follower recovery — CONFIRMED DESIGN

### 10.1 Ordinary straggling

When a follower falls behind during regular movement, the guard normally stops and waits; other followers stay with the guard if possible. The straggler attempts to catch up by an accessible route. Waiting is bounded. If reunion fails, the guard reevaluates and may resume an important task; the guard normally does not hunt for every delayed follower. Direct danger can interrupt waiting.

### 10.2 Independent flight and lost contact

A civilian deliberately fleeing from fear differs from an ordinary straggler. The guard need not abandon the rest of the group to chase the fleeing civilian. Return is conditional on safety, courage, proximity and former leader availability; it is not automatic. Membership may be temporarily reserved while reunion remains plausible. When separation genuinely becomes final, the slot opens to another recruit.

A follower who loses contact with a living leader can remember the last genuinely known location/direction, attempt a plausible reunion, and eventually give up when reunion is unrealistic. Do not provide perpetual knowledge of the living leader's current coordinates.

### 10.3 Leader death

Knowledge of death must come from plausible observation/communication. Once aware, followers reevaluate and may seek another nearby guard with room, using a physically accessible route. No teleportation, instantaneous cross-map reassignment, or omniscient discovery of leader death. If no suitable leader is available, resume individual safety/alarm behavior.

### 10.4 Assistance with a missing follower

A guard responding to an ally's request should bring **all members of the current group**. If a follower is temporarily behind, primarily use bounded waiting. If reunion cannot happen in time, the guard may refuse the request; the guard must not deliberately abandon a still-current follower merely to arrive faster.

If membership genuinely ends under the separation rules, reevaluate assistance with the actual remaining group. Do not arbitrarily end membership just to evade this obligation. This rule does not prohibit immediate self-defense or forced retreat under direct danger. General permission to reevaluate after waiting is not permission to leave an active follower behind for faster assistance.

## 11. Temporary cooperation between guard patrols — CONFIRMED DESIGN

### 11.1 Purpose, equality, and scope

During ALARM, independent guard patrols may temporarily cooperate because of known threats or a shared local objective: checking a dangerous area, patrolling a common local sector, protecting civilians, covering withdrawal, or supporting an encounter.

Guards remain peers, with no permanent commander. Each controls their own civilian followers (up to two; recruitment is optional), and retains tactical judgment. Do not merge followers into one centrally controlled group. Cooperation does not grant shared omniscient knowledge.

### 11.2 Actual agreement on dynamic common points

The confirmed model is **a shared objective with dynamically selected and mutually agreed navigation points**. After exchanging locally available information, guards jointly select an accessible next point serving that objective. Consider known incidents/reports, relevance to the shared goal, accessibility for each patrol, observation opportunities, territorial responsibility, safety and obstacles.

The point is agreed only after actual local communication. Independently running identical rules is insufficient when guards possess different knowledge. Equally appropriate alternatives require a consistent tie-break so an agreement is reached; the precise tie-break algorithm remains an implementation choice, not a permanent leader appointment.

These are dynamically chosen points, not markers permanently preplaced solely for joint patrols. Each guard follows individual navigation to the agreed point with their own companions. A point unreachable for a participating patrol is not a valid common destination.

### 11.3 Waiting and combat interruption

An early patrol may wait at an appropriate accessible position for a limited time while continuing to observe. If the other remains absent, reevaluate the shared task: continue independent work or a safe part of the original task if justified. Do not endlessly search for the other patrol. Ordinary delay does not automatically dissolve the alliance.

A discovered threat can interrupt common movement. Each guard evaluates it independently. The other guard may assist if informed or directly aware and intervention makes sense. After the encounter, reevaluate the original objective and resume if still relevant/feasible. A brief fight or ordinary delay does not automatically terminate cooperation.

### 11.4 Outcomes, separation, and renewed meetings

Keep these meanings distinct:

| Outcome | Meaning |
|---|---|
| Completed | The agreed goal was actually achieved |
| Interrupted | A more urgent event temporarily took precedence; continuation may remain relevant |
| Canceled | The common goal is unnecessary or obsolete |
| Infeasible | The task cannot be completed safely or accessibly |
| Cooperation ended | Patrols separated; the original task/incident may remain unresolved |

Separation can follow completion, cooperation no longer helping, expired waiting for a missing ally, a higher-priority obligation, inaccessible/excessively dangerous continuation, or obsolete information/objective. Ending cooperation does not falsely complete its incident.

After separation each patrol reevaluates its relevant tasks and territorial duties; return requires ordinary movement. A later meeting does **not** automatically recreate the alliance: a fresh valid reason and new local agreement are required. Avoid immediate repeated merge/split oscillation. ALARM territorial responsibilities persist throughout; cooperation is not an excuse to gather all five guards and leave every other sector undefended.

## 12. Priest boundary — CONFIRMED HIGH-LEVEL DESIGN

The priest is an unarmed, non-combat morale/leadership NPC. His high-level presence can suppress ordinary civilian flight and help organize defense; he has high priority for raising a credible alarm. These are confirmed design boundaries, not claims of implemented influence.

Detailed Priest AI, exact morale mechanics, the relationship to guard command, and the role at ORGANIZED_DEFENSE are deferred to a separate design discussion. Do not infer a commander hierarchy, immunity to all fear, command radius, morale formula, or specialized defense ability. The existing peaceful PriestRoutine is an implementation foundation only (§13).

## 13. CURRENT IMPLEMENTATION and discrepancy register

**Актуализировано 04.11.2026 после реализации.** Подтверждённый дизайн разделов 2–12 сохранён. Первоначальный аудит описывал автоматический ALARM по очкам, гражданские реакции стражи и отсутствие сопровождения; эти ограничения заменены актуальным состоянием ниже.

| Компонент | Реализовано | Граница / ограничение |
|---|---|---|
| `scripts/guard_ai.gd` | Девять состояний, B2-оценка локальных врагов/союзников/состояния, задачи и прерывания, ограниченное преследование, динамический поиск, отступление, расследование, помощь/отказ и выбор колокола | Начальная эвристика прототипа, не окончательный баланс. Помощь — подход к событию либо известной точке отхода союзника, затем обычное локальное боевое решение; специальных формаций/дальнего прикрытия нет. |
| `scripts/guard_memory.gd` | Ограниченная память задач, источник/достоверность/исходное время/incident ID, pending/active/interrupted/completed/canceled/expired/infeasible, дедупликация и последние исходы | Incident ID основан на личности наблюдаемого противника; объединение разных неизвестных противников в один крупный инцидент не реализовано. |
| `scripts/guard_patrol.gd` | Прежние пять стражников, три маршрута, пост и физическая смена; при SUSPICION короче остановки наблюдения | Мирный учёт мест у поста остаётся прежним общим служебным механизмом и не используется как источник тактического знания. ALARM использует динамические точки территории своего маршрута. |
| `scripts/village_defense.gd` | Миссионные часы, локальные физические запросы, проверка видимости/доступности, динамические точки, местная доставка и физический колокол на обеих картах | Инициализация не является общим трекером угроз. Нет координат при ALARM. При произвольной плотности неподвижных тел возможен затор; неудачная навигация завершается как infeasible, не как достижение цели. |
| `scripts/village_alert.gd` | SUSPICION учитывает принятые местные сообщения по исходному incident ID; частные события не начисляют очки. ALARM устанавливается физическим колоколом | Прежний `alarm_threshold` оставлен для сериализации и не используется для ALARM. Колокол удерживает ALARM. До звона очки затухают и могут вернуть NORMAL, а гражданская передача может повысить подозрение. Это расхождения с §3. ORGANIZED_DEFENSE автоматически не назначается. |
| `scripts/villager_local_warning.gd`, `villager_threat_detection.gd`, `villager_threat_reaction.gd` | Прежние гражданские реакции сохранены; зрение использует локальный физический запрос. Предупреждение гражданского даёт GuardAI происхождение настоящего наблюдения. Стража использует одну наследованную ретрансляцию, запросы помощи и местные подтверждения ответа | Гражданские получатели сохраняют прежнюю однопереходную реакцию. Подтверждение ответа не является наблюдением и не ретранслируется. Соглашение патрулей не обходит предел ретрансляции. |
| `scripts/civilian_escort.gd` | Приглашение/отказ, два спутника, один лидер, индивидуальная навигация, паника/условное возвращение, резервирование места, распад связи и местный поиск замены лидера, местная деятельность и личная память опасных мест при ALARM | У места сбора без лидера не возникает организованное ополчение. Нет удалённого знания смерти лидера. |
| Оружие спутников | Одно решение 60% при вступлении, мгновенный выбор инструмента по роли, `armed` и метаданные `civilian_weapon`; внешний hook `mobilize_civilians()` при уже установленном ORGANIZED_DEFENSE | В проекте нет предметной системы. Идентификатор оружия не меняет прежние урон/скорость/дальность атак. Направленный баланс «здоровый страж сильнее одного зомби» не обеспечивается новыми числами и не объявляется проверенным. |
| Временные союзы | Местное предложение/принятие общей динамической точки, проверка маршрута каждого патруля/спутника, задача GROUP_PATROL, прерывание, ограниченное ожидание и отдельное окончание связи, запрет повтора по прежнему основанию | Один союз пары патрулей на стражника; центрального командира нет. Точка имеет допустимый радиус встречи для двух физических тел. Многосторонние союзы и специализированное фланкирование остаются расширениями. |
| `scripts/villager.gd`, `scripts/zombie.gd` | Подключение перед мирным циклом; существующие взаимные боевые таймеры; соседние защитники участвуют своими атаками; ушедшие/удалённые противники очищаются из контакта стражи | Боевые характеристики/заражение не перебалансированы; нет нового инвентаря, спецэффектов и строя. |
| Священник | Прежний PriestRoutine; минимальная возможность физически поднять тревогу при серьёзной лично замеченной угрозе; безоружен | Полный ИИ, мораль, подавление обычного бегства и командование не реализованы. |

Инициализация выполняется из `scripts/test_map.gd` для обеих миссий. При отсутствии авторских узлов создаются `VillageDefense`, `GuardAI` и `CivilianEscort`; заранее добавленные одноимённые компоненты используют свои Inspector-настройки. Сцены, геометрия, navmesh, население и боевые характеристики не переписывались. Пауза и остановка миссии наследуются от её process mode. Параметры, проверки и ручная приёмка — [TDD §9.12](technical_design.md#912-тактическая-стража-и-сопровождение).

**Исправления по видео 04.11.2026:** плотный контакт не отменяется каждой переоценкой отступления и не откладывает таймер удара. Удалённые спутники очищаются по индексу, ожидание сохраняет патрульную цель, скорость группы учитывает спутников. Подход к кандидату остаётся местным и территориальным; приглашение не гарантирует согласие. Мирное безопасное ожидание при ALARM использует отдельные доступные места, не одну координату маркера. Затухание подозрения начинается после 90 с; ALARM от колокола не затухает. Новые регрессионные сценарии и ограничения — [TDD §9.13](technical_design.md#913-исправления-по-видеозаписям-и-отладчику-04112026).
## 14. Deferred decisions and unresolved ambiguities

Do not invent answers to these questions:

- Detailed Priest AI, morale effects, guard-command relationship, and defense role.
- Полное поведение при ORGANIZED_DEFENSE, командование, распределение патрулей, координация и порядок мобилизации. Universal eligible civilian arming is already confirmed (§9).
- Будущий общий отбой. В MVP все глобальные уровни сохраняются до конца миссии.
- Numerical waiting, search, task expiry, commitment and cooldown durations; reaction tuning specific to future guards.
- Exact perception/communication/cohesion radii, pursuit limits, search-area sizes and movement distances.
- Exact bounded task-list capacity and retention/eviction tuning; 3–5 was illustrative.
- Numerical damage, HP, attack rates, formulas, weapon weights/balance and future ranged guard details.
- Advanced civilian mobilization and fortification; later monster races and advanced evolutions.

Implementation/tuning details still to specify include the precise incident-reconciliation heuristic, task credibility representation, waypoint agreement/tie-break protocol, when temporarily reserved follower membership finally expires, and how a later genuinely new recruitment is distinguished from continuation for equipment decisions. The confirmed constraints above remain binding; these details must not introduce infinite hearsay, fresh timestamps for old evidence, automatic alliance renewal, or repeated per-frame equipment rerolls.

Use explicitly unset configurable parameters for future tuning (for example search duration, follower wait duration, allied-patrol wait duration, task expiry, pursuit limits, and task capacity). These names are illustrative placeholders, not existing Inspector exports or selected values. Apart from confirmed counts/probabilities and approximate search-point guidance, this record establishes no new numbers.

## 15. Behavioral acceptance matrix — future implementation criteria

These rows preserve the original design acceptance criteria. Automated contract and physical integration tests now cover the prototype; actual scope and limitations are recorded in §18 and TDD §9.12. A scenario row alone is not proof of a test pass.

| # | Situation | Expected behavior / acceptance evidence |
|---|---|---|
| 1 | NORMAL, no threat | Follow established route and physical post relief; no invented incident or group. |
| 2 | Suspicion during normal patrol | Heightened vigilance/intensified patrol while generally retaining territory/routes; assess local evidence. |
| 3 | Firsthand sighting of one zombie | Recognize with ordinary perception; B2 evaluates enemy, condition, terrain and support rather than blindly attack/flee. |
| 4 | Peasant report needing checking | Retain source, original age/location/reliability; investigate when appropriate; no automatic bell or live enemy tracking. |
| 5 | Manageable isolated threat resolved | May engage and defeat it; reevaluate wider evidence, with no mandatory bell activation. |
| 6 | Overwhelming threat | Choose accessible relative safety, assess support and physical alarm attempt; bell may be blocked/interrupted. |
| 7 | Visual contact lost | Stop live position updates; one temporary area around last genuine location, about 2–3 dynamic accessible points or fewer valid ones. |
| 8 | Search completed at NORMAL / SUSPICION / ALARM | Reevaluate urgent tasks first; otherwise ordinary patrol / intensified patrol / defensive territorial activity respectively. Completion does not prove death. |
| 9 | Several reports of same incident | Reconcile existing incident/task, preserve evidence provenance; no unbounded duplicate task growth. |
| 10 | Reports of independent nearby incidents | Keep incidents distinct despite proximity. |
| 11 | A eyewitness warns B, B warns C | Allow B's one retransmission; C cannot relay inherited report without personal reconfirmation; original age/source/incident survive. |
| 12 | Repeated assistance call, no new facts | No automatic priority increase or freshness reset. |
| 13 | Assistance call with new enemies/escalation/location | Update actual evidence and reevaluate urgency contextually. |
| 14 | Two guards hear same call | A responder may locally acknowledge response; peers consider it without global knowledge or assuming victory. |
| 15 | Bell versus helping an ally | Decide from urgency, distance, access, risk, companions and delay consequences; neither choice universally wins. |
| 16 | ALARM recruit receives armed outcome | Local invitation accepted, capacity respected, individual 60% arming decision made once for recruitment; instant role-weighted equipment. |
| 17 | ALARM recruit receives unarmed outcome | Valid 40% outcome; remains useful companion with limited self-defense; no frame rerolls or forced within-group ratio. |
| 18 | Ordinary follower straggles | Guard normally waits bounded time; other follower stays, straggler catches up by accessible path; danger can interrupt. |
| 19 | Follower independently panics | No mandatory chase by leader; conditional possible reunion/reservation, eventual genuine separation frees slot. |
| 20 | Help request while follower missing | Bring all current members; wait within bounded rule and possibly refuse help instead of deliberately abandoning active follower. Immediate survival remains allowed. |
| 21 | Guard leader killed | Followers learn death plausibly, assess accessible nearby leader/capacity, move physically or resume independent safety. |
| 22 | Two patrols select a common point | Exchange local information and actually agree on dynamic objective-serving point accessible to both; consistent tie-break, no permanent commander. |
| 23 | One allied patrol arrives late | Other observes while waiting bounded time; reevaluates if absence persists, no endless ally hunt; ordinary delay alone need not dissolve alliance. |
| 24 | Joint patrol interrupted by combat | Separate tactical evaluations; help if aware/informed and sensible; preserve interrupted objective and resume only if relevant. |
| 25 | Joint goal completed | Record completion, separate if appropriate, reevaluate individual tasks/territories and move normally. |
| 26 | Patrols lose contact; waiting expires | Cooperation may end; unresolved common task may be infeasible/canceled/still relevant as evidence warrants, not falsely completed. |
| 27 | Former allies meet again | No automatic re-merge; fresh valid objective/reason and new local agreement required, with oscillation prevention. |
| 28 | Bell activates ALARM with unknown monster positions | Danger awareness without coordinates, enemy references or invented sighting; guards use existing local evidence. Score alone cannot substitute. |
| 29 | Alarmed civilian at leaderless gathering site | Generally waits for defenders; may flee/hide from immediate danger; no spontaneous organized militia. |
| 30 | Pending task expires or route proves infeasible | Remove/cancel/mark infeasible as appropriate without claiming underlying threat eliminated. |
| 31 | ORGANIZED_DEFENSE mobilization | Доступные живые необращённые крестьяне и ремесленники вооружаются в ходе физической мобилизации, священник остаётся безоружным. Переход по порогу утверждён, порядок мобилизации и командование открыты. |
| 32 | Living leader lost behind obstacles | Follower uses last-known direction/location and accessible reunion attempt, eventually gives up; no magical coordinates. |
| 33 | Bell already raised while alarm task pending | Duplicate raise-alarm objective becomes unnecessary; reassess tasks without resolving unrelated threats. |
| 34 | Cooperation would pull every guard from other sectors | Consider actual local need and territorial duties; no automatic village-wide concentration. |

## 16. Audit against the documentation task

This table preserves the original documentation-task audit. References to unexecuted scenarios describe that initial record; current implementation and executed validation are recorded in §13 and §18.

| User prompt section | Preserved content |
|---|---|
| 1 — Repository/workflow | Canonical specification, cross-references, status separation, source discrepancies, decision index and change log (§1, §13, §17) |
| 2 — Context | Genre, commands, zombies, real-time individual combat, 30 inhabitants and existing five-guard/three-route foundation (§1) |
| 3 — Principles | Local information, perception, B2 and no global army-power replacement (§2) |
| 4 — Village alerts | Four levels, physical bell, no score-driven notification, deferred defense/stand-down (§3) |
| 5 — Individual guard | Tactical choices, dynamic retreat, bounded pursuit, last-known dynamic search and level-dependent return (§4) |
| 6 — Reports/alarm | Contextual report verification and post-combat alarm decisions, physical interaction, duplicate alarm task (§3–4) |
| 7 — States | All nine states and five independent dimensions; follower group is not GROUP_PATROL (§5) |
| 8 — Tasks | Bounded relevance-aware memory, statuses, interruptions, situational priorities, anti-oscillation, removal (§6) |
| 9 — Patrol by level | Routes, vigilance, flexible territorial ALARM, no invented organized-defense patrol (§3) |
| 10 — Recruitment | Individual civilian safety preferences, leaderless gathering behavior, active invitations, refusal and two-follower cap (§8) |
| 11 — Followers | Flexible support/combat, own survival/navigation, no distant hunts, courage and plausible reassignment (§8, §10) |
| 12 — Arming | 60%/40%, full eligible defense arming, instant acquisition, role-weighted weapons, priest unarmed, directional balance only (§9) |
| 13 — Cohesion | Bounded waiting, independent flight, reserved membership, living/dead leader recovery, no abandonment for assistance (§10) |
| 14 — Communication | Provenance, one retransmission, requests, incident reconciliation, unchanged repeats and local acknowledgement (§7) |
| 15 — Cooperation | Peer equality, actual dynamic-point agreement, bounded waits, interruptions, outcome distinctions, separation/territory/no automatic re-merge (§11) |
| 16 — Priest | Confirmed non-combat/morale/alarm boundary and deferred specifics (§12) |
| 17 — Scenarios | All 30 requested scenarios plus four adjacent constraints, explicitly unexecuted (§15) |
| 18 — Deferred | No fabricated timings, ranges, capacity, combat values or unresolved mechanics (§14) |
| 19 — Deliverables | Canonical design, linked summaries, status checklist, discrepancies, ambiguities and documentation audit (§1–17 and linked documents) |

## 17. Documentation change log

- **2026-11-04, местное расследование:** закреплены гонец, встреча и группа до колокола, приоритет доступного стражника, послебоевая проверка и местный возврат к занятиям без общего отбоя. Подробности — [TDD §9.16](technical_design.md#916-свидетель-стража-местное-расследование-и-возврат-к-занятиям).

- **2026-11-04, запись 17:52:** очевидец кричит и во время бегства; принятая местная передача повышает подозрение по прежнему incident ID. После непосредственного бегства/истечения координат гражданский сохраняет решение дойти до своего дома и стоять с S. Приглашение местной стражи может заменить этот план сопровождением; после потери группы домашний запасной план остаётся. Для отказавшегося/не приглашённого очевидца короткая тишина не открывает обычную деятельность. Интерьеры/баррикады и отбой укрытия отложены. Реализация и проверка — [TDD §9.15](technical_design.md#915-крик-на-бегу-и-стойкое-укрытие-жителей).

- **2026-11-04, уточнение после записей 17:05/17:10:** закреплены приоритет спутников после колокола, счёт только распространённых сведений, местная деятельность и уход от известной массовой угрозы к дому/мастерской. Реализация, начальные параметры и выполненные проверки — TDD §9.14.

- **2026-11-04, исправления по видео:** уточнены текущие самозащита, таймеры контакта, очистка спутников, ограниченный обход, места ожидания, сохранение патрульной цели и задержка затухания подозрения; результаты в TDD §9.13.

- **2026-11-04, реализация:** подключены стража, сопровождение, местная связь и физический колокол; обновлены текущие статусы, ограничения и проверки. Подтверждённые правила сохранены.
- **2026-11-04:** Preserved the complete confirmed guard design as a canonical specification; added state/lifecycle tables, implementation gaps, unresolved decisions, acceptance matrix and prompt coverage audit. Linked it from the GDD, TDD and large-village documentation, with explicit notices distinguishing current score-based alarm/single-hop warnings from the intended physical bell and provenance-aware guard protocol. Documentation only; no gameplay or runtime validation claims added.

## 18. Проверки реализации и оставшиеся границы

Добавлены `tests/guard_ai_validation.gd` (контракты состояний, памяти, сообщений, групп и соглашений с привязкой к 52 пунктам задания) и `tests/guard_ai_world_validation.gd` (физическое расследование, подход/взаимодействие с колоколом, взаимный урон, непрозрачная стена, движение двух патрулей к согласованной точке, реальное боевое прерывание союза, 600 независимых решений вооружения и 180 игровых секунд ALARM всех 30 NPC). Часть контрактов непосредственно вызывает API; WORLD-сценарии проверяют подключение к реальным движению/бою. Это не ручная приёмка каждой комбинации условий.

Окончательные результаты и журналы, временные defaults и инструкция наблюдения — TDD §9.12. Не объявляются готовыми полный Priest AI, мораль, переход/командование ORGANIZED_DEFENSE, отбой ALARM, окончательные оружейные различия и числовой баланс. Долгое интерактивное прохождение с произвольной плотностью толпы ещё требует приёмки.

Актуальное уточнение реализации и проверок: [TDD §9.14](technical_design.md#914-сбор-спутников-после-колокола-распространённое-подозрение-и-жизнь-мест-сбора).

Последующее уточнение поведения очевидцев, местной передачи и проверок: [TDD §9.15](technical_design.md#915-крик-на-бегу-и-стойкое-укрытие-жителей).

Текущий приоритет поиска стражи и местный возврат участников после проверки района: [TDD §9.16](technical_design.md#916-свидетель-стража-местное-расследование-и-возврат-к-занятиям).

По актуальному уточнению очевидец выбирает `R` или `S` после бегства; первыми реакциями остаются F и редкое замешательство Z с переходом в F; отдельная остановка W отменена. Гонец выбирает доступного стражника по длине безопасного пути. Отклик закрепляет точку встречи, где стражник ждёт свидетеля. Уже известное предупреждение может привести к встрече, когда стражник снова свободен. При отсутствии местной помощи гонец проверяет один наружный подход к посту, если хватает времени на безопасный путь и ожидание. Если поиск сорвался, запасная цель — свой дом. Группа начинает проверку места после личной встречи и приглашает доступную помощь по пути. [TDD §9.19](technical_design.md#919-выбор-реакции-очевидца)


### Уточнение 05.11.2026: роли и превосходящая угроза

Гражданские реакции не исполняются на NPC с активным GuardAI, включая повторное распознавание из общего цикла движения. Стражник самостоятельно оценивает местную угрозу; при превосходстве противника доступный физический колокол имеет приоритет над новым преследованием после короткого отхода. В местном расследовании эскалация немедленно освобождает гражданских спутников для собственных реакций и домашнего укрытия. Другой стражник сохраняет самостоятельные решения и локальные знания.

Договорённость о встрече ещё не является передачей свидетеля в группу. Для передачи нужен видимый контакт в `witness_contact_radius` (новый предварительный default 24); радиус обычного приглашения остаётся 60. Резервный пост — известное место, но не обещание свободного дежурного при боевом прерывании смены. Детали, ограничения и фактическая проверка — [TDD §9.20](technical_design.md#920-разделение-ролей-и-переходы-после-опасности).


### Уточнение помощи спутников в бою — 05.11.2026

Спутник с видимым лидером помогает против лично распознанного и видимого противника уже в состоянии COMBAT стражника, без ожидания физического столкновения лидера. Вооружённый спутник сближается с врагом в пределах половины contact_radius от лидера (75 по умолчанию), безоружный — только в пределах follow_distance (24). Сохраняются оценка превосходящей угрозы, индивидуальная паника и запрет дальней самостоятельной погони. Оружие и числовой урон не менялись.

Победа сама по себе не распускает патрульную группу при ALARM: участники сохраняют членство и продолжают задачи лидера, включая поиск и патруль. Исключение прежнего согласованного сценария — временная группа расследования до колокола: после проверки района участники возвращаются к обычным занятиям. Роспуск при превосходящей угрозе и потеря лидера остаются отдельными основаниями.

Проверка этого уточнения ограничена импортом и коротким запуском; игровые сценарии не запускались. Скриншот не позволяет установить членство и вооружение каждого стоящего NPC. Реальную помощь, доступность подходов в толпе и продолжение патруля необходимо проверить вручную.
