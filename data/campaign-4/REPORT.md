# Campaign 4 report · Звіт кампанії 4

[English](#english) · [Українська](#українська)

## English

This document describes how campaign 4 was carried out under its protocol,
[`PROTOCOL.md`](PROTOCOL.md): what was done as specified, what was done differently, and what was
not done, with the reasons. It also gives the results of the campaign and the analyses made after
the data.

Campaign 4 is the campaign reported in the article. It consists of 18 runs.

### Files

| File | Content |
|---|---|
| `smoke.json` | smoke test, six runs with reduced N and REPS; not for publication |
| `campaign.json` | raw results of the 18 runs, run design, environment before and after the campaign |
| `pilot.pinned.json` | pinning pilot, six runs pinned to a core |
| `pilot.free.json` | pinning pilot, six runs without pinning |
| `probe_build.json` | build flags, compiler and hot-function addresses of the representatives |
| `machine_state.txt` | machine state recorded by `prepare_machine.sh` |

The code is in the repository root:

| File | Role |
|---|---|
| `runner.py` | run design, core pinning, environment record and the pre-registered analysis |
| `measure.py` | measurement code |
| `probe.c` | minimal class representatives, built as `probe_full` with the public C API and as `probe_limited` with `Py_LIMITED_API` |
| `prepare_machine.sh` | machine preparation |
| `post_hoc.py` | sensitivity analysis, absolute differences and tier gap; not part of the protocol |
| `multiplicity_ci.py` | bootstrap intervals of the median ratios; not part of the protocol |

### Execution

#### Done as specified

The campaign measured the six cases of section 1; classes 1 and 2 were not measured. In the
representatives built from `probe.c` the deallocators release the reference to their type. The
build step checked this together with correct addition and function alignment, and a failed check
would have prevented the campaign from starting.

All 18 runs were made, each in a separate process. The design passed the balance checks recorded
in `campaign.json`: each row of the square is a permutation of the six cases, each case occupies
each position once per square, and all 30 ordered pairs of adjacent cases occur, so carryover is
balanced. The rows of each replicate were shuffled with the recorded seed 1790350596.

The empty loop was measured at the start and at the end of every run. Individual measurements
range from 55.03 to 60.51 ns, and the drift within a run has a median of −0.51 ns and ranges from
−1.94 to +1.36 ns.

Rules 1 to 5 are implemented in `runner.py`. No run met an exclusion criterion of rule 6: pinning
succeeded in all 18 runs, and the load average changed by at most 0.10 within a run.

Every run was pinned to core 2, and the affinity read back after pinning matches in all runs. In the
pilot the spread of the baseline was 12.3% with pinning and 19.0% without, so pinning was kept.

The environment was recorded before and after the campaign. SMT was disabled, leaving CPUs 0 and 2
online, and the governor was `performance` with both frequency limits at 1.6 GHz on both cores.
`PYTHONHASHSEED` was 0, and address space layout randomization was left enabled, as specified. The
machine was prepared by `prepare_machine.sh`, which records its steps in `machine_state.txt`.

In both builds every hot function starts at an offset that is a multiple of 64. The
representatives were built in a separate step before the first run.

#### Done differently

The protocol expects the boost controls to take effect at the base frequency. On this machine they
do not: with the driver's boost control off and bit 25 of the HWCR register set, the measurement
core still reached 3.03 GHz under load at the base frequency of 1.8 GHz. As the protocol prescribes
for this case, the next lower frequency, 1.6 GHz, was fixed instead and verified under load, with a
peak of 1.597 GHz.

#### Not done

There was no control platform, because only one machine was available. As section 7 anticipates, the
campaign is therefore not a measurement under the full methodology. The ratios to the baseline need
to be measured again on a control platform, while the within-run contrasts hold within the limits
shown by the sensitivity analysis.

Two related points are not deviations. The protocol requires pinning the process, not isolating
the core from the scheduler, so other tasks scheduled on the same core remain a source of
disturbance within the measurement conditions. The environment records the frequency as snapshots
at capture time rather than per case, so the constancy of the frequency within a run relies on the
frequency being fixed.

#### Observations

In four of the 108 cases the median of a case exceeds the median of its class by more than a
quarter. These are class 3 in runs 3, 11 and 14, where all seven repetitions are slow (about 106 ns
against a class median of 70.5 ns), and class 7 in run 16, where most repetitions are slow (128.6 ns
against 90.9 ns, while the fastest repetition, 93.0 ns, is normal). Runs are numbered from zero by
the `seq` field. The cause has not been established. All four cases remain in the primary analysis,
because neither exclusion criterion of rule 6 was triggered. There were no failures in the
measurement of the baseline or of the empty loop.

### Primary results

Ratios to the baseline, computed within each run (rule 2):

| Class | Median ratio | Range |
|---|---:|---|
| 3 | 1.963 | 1.811 to 3.230 |
| 4 | 2.091 | 1.984 to 2.238 |
| 5 | 2.413 | 2.241 to 2.665 |
| 6 | 24.671 | 21.905 to 27.168 |
| 7 | 2.529 | 2.346 to 3.491 |

Axis effects (rules 3 and 4), as medians of within-run differences with 95% bootstrap intervals:

| Quantity | Median | Interval |
|---|---:|---|
| state placement, public C API, 3 → 5 | +22.1% | +18.8% to +27.2% |
| state placement, limited API, 4 → 7 | +21.4% | +18.0% to +22.7% |
| level of intervention, in-object, 4 → 3 | −5.9% | −7.6% to −4.0% |
| level of intervention, table, 7 → 5 | −3.7% | −4.4% to −2.8% |
| main effect of state placement | +21.5% | +18.3% to +26.0% |
| main effect of level of intervention | −5.0% | −5.8% to −3.4% |
| interaction | +1.1% | −0.7% to +3.3% |

Both effects are present. The interval of the interaction includes zero, so each effect is reported
as a single value. Predictions 1 and 2 are confirmed.

Position effect (rule 5), as the change per position: baseline +0.14%, class 3 +0.01%, class 4
+0.43%, class 5 +0.08%, class 6 −0.47%, class 7 +1.59%. The value for class 7 is driven by run 16.

### Post hoc analyses

The following analyses were made after the data had been collected. They are not part of the
protocol and do not change the verdicts. The first three are printed by `post_hoc.py`, the last by
`multiplicity_ci.py`.

#### Sensitivity analysis

Without runs 3, 11, 14 and 16, the state placement effect is +22.0% (+19.4% to +26.2%), the effect
of the level of intervention is −5.3% (−5.8% to −4.4%), and the interaction is +1.4% (+0.9% to
+5.1%), which here excludes zero. Removing four runs breaks the balance of the three replicates of
the Williams design, so this is an estimate of the influence of the slow cases, not a primary
result.

#### Tier gap

Class 6 is outside the criterion fixed in advance. Its ratios do not overlap with those of the C
classes (a minimum of 21.905 against a maximum of 3.491), and dividing its median ratio by those of
the C classes gives a gap of 9.8 to 12.6 times.

#### Absolute differences

Over all 18 runs, the limited API adds +4.42 ns with in-object state and +3.34 ns with an external
table. The within-run difference between the two increments is +0.16 ns, with an interval from
−1.68 to +1.69 ns.

#### Bootstrap intervals of the median ratios

The intervals use the same seed, number of resamples and confidence level as the effect intervals.
They reflect run-to-run variation only.

| Class | Median ratio | 95% bootstrap interval |
|---|---:|---|
| 3 | 1.963 | 1.933 to 2.042 |
| 4 | 2.091 | 2.060 to 2.128 |
| 5 | 2.413 | 2.378 to 2.481 |
| 6 | 24.671 | 24.065 to 25.414 |
| 7 | 2.529 | 2.481 to 2.585 |

## Українська

Цей документ описує, як кампанію 4 виконано за її протоколом, [`PROTOCOL.md`](PROTOCOL.md): що
зроблено за протоколом, що зроблено інакше і що не зроблено, з причинами. Він також подає
результати кампанії та аналізи, виконані після отримання даних.

Кампанія 4 є кампанією статті. Вона складається з 18 прогонів.

### Файли

| Файл | Зміст |
|---|---|
| `smoke.json` | димовий тест, шість прогонів зі зменшеними N і REPS, дані не для публікації |
| `campaign.json` | сирі дані 18 прогонів, план прогонів, середовище до і після кампанії |
| `pilot.pinned.json` | пілотне дослідження прив'язки, шість прогонів з прив'язкою до ядра |
| `pilot.free.json` | пілотне дослідження прив'язки, шість прогонів без прив'язки |
| `probe_build.json` | прапорці збірки, компілятор і адреси гарячих функцій представників |
| `machine_state.txt` | стан машини, записаний `prepare_machine.sh` |

Код лежить у корені репозиторію:

| Файл | Роль |
|---|---|
| `runner.py` | план прогонів, прив'язка до ядра, запис середовища і аналіз, зафіксований наперед |
| `measure.py` | вимірювальний код |
| `probe.c` | мінімальні представники класів, збираються як `probe_full` із загальним публічним C API і як `probe_limited` з `Py_LIMITED_API` |
| `prepare_machine.sh` | підготовка машини |
| `post_hoc.py` | аналіз чутливості, абсолютні різниці й розрив ярусів, до протоколу не входить |
| `multiplicity_ci.py` | бутстреп-інтервали медіанних кратностей, до протоколу не входить |

### Виконання

#### Зроблено за протоколом

Кампанія виміряла шість випадків розділу 1, класи 1 і 2 не вимірювалися. У представниках, зібраних
з `probe.c`, деалокатори віддають посилання на свій тип. Етап збірки перевірив це разом з
правильністю додавання і вирівнюванням функцій, а за невдалої перевірки кампанія не запустилася б.

Виконано всі 18 прогонів, кожен окремим процесом. План пройшов перевірки врівноваженості, записані
в `campaign.json`: кожен рядок квадрата є перестановкою шести випадків, кожен випадок стоїть на
кожній позиції раз за квадрат, і трапляються всі 30 упорядкованих пар сусідніх випадків, тож
післядію врівноважено. Рядки кожного повторення перемішано за записаним зерном 1790350596.

Порожній цикл виміряно на початку й у кінці кожного прогону. Окремі виміри лежать від 55,03 до
60,51 нс, а дрейф усередині прогону має медіану −0,51 нс і розмах від −1,94 до +1,36 нс.

Правила з 1 по 5 реалізовано в `runner.py`. Жоден прогін не підпав під ознаки вилучення за правилом 6:
прив'язка вдалася в усіх 18 прогонах, а середнє навантаження за прогін змінювалося щонайбільше на
0,10.

Кожен прогін прив'язано до ядра 2, і перечитана після прив'язки маска збігається в усіх прогонах. У
пілотному дослідженні розмах бази відліку становив 12,3 % з прив'язкою і 19,0 % без неї, тож
прив'язку збережено.

Середовище записано до і після кампанії. Одночасну багатопотоковість вимкнено, увімкненими лишилися
процесори 0 і 2, а регулятор частоти `performance` мав обидві межі частоти на рівні 1,6 ГГц на обох
ядрах. `PYTHONHASHSEED` дорівнював 0, а рандомізацію адресного простору лишено ввімкненою, як і
передбачає протокол. Машину підготував `prepare_machine.sh`, який записує свої кроки в
`machine_state.txt`.

В обох збірках кожна гаряча функція починається зі зміщення, кратного 64. Представників зібрано
окремим кроком до першого прогону.

#### Зроблено інакше

Протокол розраховує, що важелі прискорення діють на базовій частоті. На цій машині вони не діють:
за вимкненого важеля прискорення драйвера і встановленого біта 25 регістра HWCR вимірювальне ядро
під навантаженням на базовій частоті 1,8 ГГц усе одно розганялося до 3,03 ГГц. Як і передбачає
протокол для такого випадку, натомість зафіксовано наступну нижчу частоту, 1,6 ГГц, і перевірено її
під навантаженням, пік становив 1,597 ГГц.

#### Не зроблено

Контрольної платформи не було, бо була доступна лише одна машина. Тому, як і передбачає розділ 7,
кампанія не є вимірюванням за повною методикою. Кратності відносно бази відліку потребують
повторного вимірювання на контрольній платформі, а попарні порівняння всередині прогону чинні в
межах, які показує аналіз чутливості.

Два суміжні пункти відступами не є. Протокол вимагає прив'язки процесу, а не ізоляції ядра від
планувальника, тож стороннє планування на тому самому ядрі лишається джерелом збурень у межах умов
вимірювання. Частоту запис середовища подає разовими знімками на момент запису, а не по випадках,
тож сталість частоти в межах прогону спирається на її фіксацію.

#### Спостереження

Чотири виміри випадку зі 108 перевищують медіану свого класу більш ніж на чверть. Це клас 3 у
прогонах 3, 11 і 14, де повільні всі сім повторів (близько 106 нс проти медіани класу 70,5 нс), і
клас 7 у прогоні 16, де повільна більшість повторів (128,6 нс проти 90,9 нс, а найшвидший повтор,
93,0 нс, у нормі). Прогони пронумеровано від нуля за полем `seq`. Причину уповільнення не
встановлено. Усі чотири виміри лишено в основному аналізі, бо жодна з двох ознак вилучення за
правилом 6 не спрацювала. Збоїв виміру бази відліку і порожнього циклу не було.

### Основні результати

Кратності відносно бази відліку, пораховані всередині кожного прогону (правило 2):

| Клас | Медіана кратності | Розмах |
|---|---:|---|
| 3 | 1,963 | від 1,811 до 3,230 |
| 4 | 2,091 | від 1,984 до 2,238 |
| 5 | 2,413 | від 2,241 до 2,665 |
| 6 | 24,671 | від 21,905 до 27,168 |
| 7 | 2,529 | від 2,346 до 3,491 |

Ефекти осей (правила 3 і 4), тобто медіани різниць усередині прогону з бутстреп-інтервалами на рівні
95 %:

| Величина | Медіана | Інтервал |
|---|---:|---|
| розміщення стану, загальний C API, 3 → 5 | +22,1 % | від +18,8 % до +27,2 % |
| розміщення стану, обмежений API, 4 → 7 | +21,4 % | від +18,0 % до +22,7 % |
| рівень втручання, стан в об'єкті, 4 → 3 | −5,9 % | від −7,6 % до −4,0 % |
| рівень втручання, таблиця, 7 → 5 | −3,7 % | від −4,4 % до −2,8 % |
| ефект розміщення стану | +21,5 % | від +18,3 % до +26,0 % |
| ефект рівня втручання | −5,0 % | від −5,8 % до −3,4 % |
| взаємодія | +1,1 % | від −0,7 % до +3,3 % |

Обидва ефекти наявні. Інтервал взаємодії містить нуль, тож кожен ефект подано одним числом. Прогнози
1 і 2 підтверджено.

Позиційний ефект (правило 5), тобто зміна значення на одну позицію: база відліку +0,14 %, клас 3
+0,01 %, клас 4 +0,43 %, клас 5 +0,08 %, клас 6 −0,47 %, клас 7 +1,59 %. Значення для класу 7 дає
прогін 16.

### Додаткові аналізи після даних

Ці аналізи виконано після отримання даних. До протоколу вони не входять і вердиктів не змінюють.
Перші три друкує `post_hoc.py`, останній `multiplicity_ci.py`.

#### Аналіз чутливості

Без прогонів 3, 11, 14 і 16 ефект розміщення стану становить +22,0 % (від +19,4 % до +26,2 %), ефект
рівня втручання −5,3 % (від −5,8 % до −4,4 %), а взаємодія +1,4 % (від +0,9 % до +5,1 %), і тут її
інтервал нуля не містить. Вилучення чотирьох прогонів порушує рівність трьох повторень плану
Вільямса, тож це оцінка впливу вимірів випадку з уповільненням, а не основний результат.

#### Розрив ярусів

Клас 6 лежить поза критерієм, зафіксованим наперед. Його кратності не перекриваються з кратностями
класів на C (мінімум 21,905 проти максимуму 3,491), а ділення його медіанної кратності на медіанні
кратності класів на C дає розрив від 9,8 до 12,6 раза.

#### Абсолютні різниці

По всіх 18 прогонах обмежений API додає +4,42 нс для стану в об'єкті і +3,34 нс для зовнішньої
таблиці. Різниця між цими прибавками всередині прогону становить +0,16 нс з інтервалом від −1,68
до +1,69 нс.

#### Бутстреп-інтервали медіанних кратностей

Інтервали мають те саме зерно, кількість повторних вибірок і рівень, що й інтервали ефектів. Вони
відбивають лише розкид між прогонами.

| Клас | Медіана кратності | Бутстреп-інтервал 95 % |
|---|---:|---|
| 3 | 1,963 | від 1,933 до 2,042 |
| 4 | 2,091 | від 2,060 до 2,128 |
| 5 | 2,413 | від 2,378 до 2,481 |
| 6 | 24,671 | від 24,065 до 25,414 |
| 7 | 2,529 | від 2,481 до 2,585 |
