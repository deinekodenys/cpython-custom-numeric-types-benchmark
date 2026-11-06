# CPython Custom Numeric Types Benchmark

[English](#english) · [Українська](#українська)

## English

Measurement code and raw data for the article *Extending CPython with Custom Numeric Types. Classes
of Architectural Decisions and a Predictive Cost Model for a Numeric Operation*. Each class of
architectural decisions is measured on a minimal representative, an implementation with stub
arithmetic. The representative follows the dispatch route of its class in full, its representation
has the size proper to the class, and its state is read exactly where the class places it.

The numbers in the article come from campaign 4. Its protocol is summarized in
[`data/campaign-4/PROTOCOL.md`](data/campaign-4/PROTOCOL.md), and its execution and results are
described in [`data/campaign-4/REPORT.md`](data/campaign-4/REPORT.md). Campaigns 1 to 3 were
replaced, and their data are kept in [`data/campaigns-1-3/`](data/campaigns-1-3/).

### Contents

| File | Role |
|---|---|
| `prepare_machine.sh` | prepares the machine for a campaign and records its state |
| `run_campaign.sh` | builds the representatives, then runs the smoke test, the pinning pilot and the campaign |
| `runner.py` | run design, core pinning, environment record and the pre-registered analysis |
| `measure.py` | measurement code |
| `probe.c` | minimal class representatives in C |
| `post_hoc.py` | sensitivity analysis, absolute differences and tier gap, added after the data |
| `multiplicity_ci.py` | bootstrap intervals of the median ratios, added after the data |
| `data/` | raw data of the campaigns, their protocols and reports |

### Reproducing the analysis

The analysis needs Python 3.8 or newer and nothing beyond the standard library. The commands are
run from the repository root.

```sh
python3 runner.py --analyze data/campaign-4/campaign.json
```

This is the pre-registered analysis. It prints the ratio of every class to the baseline with its
range, the 2 × 2 design with bootstrap intervals and the verdict on each effect, the position
effect, the drift of the empty loop and the observed CPU sets.

```sh
python3 post_hoc.py data/campaign-4/campaign.json
```

Analyses added after the data. The script finds the slow cases, whose median exceeds the median of
their class by more than a quarter, and repeats the ratio table and the 2 × 2 design without the
runs that contain them. It then prints the absolute differences in nanoseconds and the tier gap
over all runs. The option `--exclude` names the runs to leave out instead, for example
`--exclude 3,11`.

```sh
python3 multiplicity_ci.py data/campaign-4/campaign.json
```

The script prints the bootstrap interval of the median ratio of every class to the baseline next to
the range of the ratio.

The resampling seed is fixed in `runner.py`, so the commands print the same numbers every time. They
match the sections [Primary results](data/campaign-4/REPORT.md#primary-results) and
[Post hoc analyses](data/campaign-4/REPORT.md#post-hoc-analyses) of the campaign 4 report.

### Running a campaign

A campaign needs Linux with systemd on an AMD or Intel x86-64 processor, CPython 3.12 with its
headers, gcc and root access. On AMD processors `prepare_machine.sh` also needs msr-tools. The
commands are run from the repository root. Each campaign has its own directory `data/campaign-N`,
which `prepare_machine.sh` creates with the next free number. Every file a campaign produces is
written there, except the built representatives, which stay in the repository root.

A campaign runs under a protocol written before its first run. Write the protocol of the new
campaign to `PROTOCOL.md` in the campaign directory: `run_campaign.sh` does not start without this
file, and `runner.py` stores its checksum with the results. The protocol text of the published
campaigns is not part of the repository.

#### 1. Prepare the machine

Log in on a text console, for example with Ctrl+Alt+F3, because the script stops the graphical
session, and run

```sh
sudo ./prepare_machine.sh 2
```

The argument is the measurement core, core 2 in these examples. Any online core other than 0 will
do. Without the argument the script takes the highest numbered one.

The script checks mains power, stops the graphical session and background services, checks that no
browser or package manager is running, switches SMT and frequency boost off, sets the `performance`
governor at a fixed frequency and routes interrupts to core 0. It then waits until the load average
falls below 0.5, loads the measurement core and checks that the core holds the frequency under
load. The frequency is the highest one the driver offers, or the next lower one if the core boosts
above it under load. A frequency in kHz can also be given explicitly:

```sh
sudo FREQ_KHZ=1600000 ./prepare_machine.sh 2
```

Once its preconditions are met, the script creates the campaign directory, and it prints the name
of the directory at the end. A directory left by an earlier attempt that holds no results yet is
reused. The script stops at the first step that fails. The machine state, including a failed step,
is written to `machine_state.txt` in the campaign directory, and `runner.py` stores the checksum of
this file with the results. The settings last until the next reboot. The steps follow
[section 6](data/campaign-4/PROTOCOL.md#6-environment) of the campaign 4 protocol.

#### 2. Build the representatives

As a normal user:

```sh
./run_campaign.sh 2 build
```

The script builds `probe_full.so` with the public C API and `probe_limited.so` with `Py_LIMITED_API`
from `probe.c`, and writes the build parameters to `probe_build.json` in the campaign directory. It
then checks that both representatives add correctly, release the reference to their type and have
their hot functions aligned to 64 bytes. The build is a separate command, so that compilation never
runs right before a measurement.

#### 3. Measure

```sh
./run_campaign.sh 2
```

The script first checks that the built modules still match `probe.c` and the interpreter. It then
runs the smoke test and the pinning pilot, and asks for confirmation before the campaign of 18
runs. At the end of the campaign `runner.py` prints the pre-registered analysis of the new data.
The results are written to `smoke.json`, `pilot.pinned.json`, `pilot.free.json` and
`campaign.json` in the campaign directory. The file `smoke.json` is a sanity check of the setup.
`run_campaign.sh` uses the campaign directory with the highest number and refuses one that already
holds `campaign.json`.

The stages can also be run one at a time as `./run_campaign.sh 2 smoke`, `pilot` or `campaign`.
Each call keeps the result files already present under names with a timestamp, including those of
the previous stage.

| Variable | Meaning | Default |
|---|---|---|
| `CAMPAIGN_DIR` | campaign directory | `data/campaign-N` with the highest N |
| `PY` | path to the CPython 3.12 interpreter | the first found of `python3.12`, `/opt/python3.12/bin/python3.12` and `/usr/bin/python3.12` |
| `RUNS` | number of campaign runs | 18 |
| `YES` | `1` continues after the pilot without asking | asks |
| `PYTHONHASHSEED` | hash seed | 0 |

Reboot the machine after the campaign to restore its settings.

#### Repeating the run order

The order of the runs is shuffled with a seed stored in the field `design.row_seed` of
`campaign.json`. To repeat the order of a published campaign, build the representatives and call
`runner.py` directly from the campaign directory with that seed in place of `SEED`:

```sh
cd data/campaign-N
PYTHONHASHSEED=0 python3.12 ../../runner.py --core 2 --runs 18 --seed SEED --out campaign.json
```

## Українська

Вимірювальний код і сирі дані до статті «Вбудовування користувацьких числових типів у CPython. Класи
архітектурних рішень та модель прогнозування вартості числової операції». Кожен клас архітектурних
рішень вимірюється на мінімальному представнику, тобто на реалізації з арифметикою-заглушкою.
Представник повністю відтворює маршрут диспетчеризації свого класу, його подання має розмір,
властивий класу, а стан читається саме там, де клас його розміщує.

Числа статті взято з кампанії 4. Її протокол стисло подано в
[`data/campaign-4/PROTOCOL.md`](data/campaign-4/PROTOCOL.md), а виконання і результати описано в
[`data/campaign-4/REPORT.md`](data/campaign-4/REPORT.md). Кампанії з 1 по 3 заміщено, а їхні
дані лежать у [`data/campaigns-1-3/`](data/campaigns-1-3/).

### Вміст

| Файл | Роль |
|---|---|
| `prepare_machine.sh` | готує машину до кампанії і записує її стан |
| `run_campaign.sh` | збирає представників, потім запускає димовий тест, пілотне дослідження прив'язки і кампанію |
| `runner.py` | план прогонів, прив'язка до ядра, запис середовища і аналіз, зафіксований наперед |
| `measure.py` | вимірювальний код |
| `probe.c` | мінімальні представники класів на C |
| `post_hoc.py` | аналіз чутливості, абсолютні різниці й розрив ярусів, додані після даних |
| `multiplicity_ci.py` | бутстреп-інтервали медіанних кратностей, додані після даних |
| `data/` | сирі дані кампаній, їхні протоколи і звіти |

### Відтворення аналізу

Для аналізу потрібен Python 3.8 або новіший і нічого, крім стандартної бібліотеки. Команди
запускаються з кореня репозиторію.

```sh
python3 runner.py --analyze data/campaign-4/campaign.json
```

Аналіз, зафіксований наперед. Скрипт друкує кратність кожного класу відносно бази відліку з
розмахом, повний факторний план два на два з бутстреп-інтервалами і вердиктом щодо кожного ефекту,
позиційний ефект, дрейф порожнього циклу і фактичні набори ядер.

```sh
python3 post_hoc.py data/campaign-4/campaign.json
```

Аналізи, додані після даних. Скрипт знаходить виміри випадку з уповільненням, медіана яких перевищує
медіану їхнього класу більш ніж на чверть, і повторює таблицю кратностей і план два на два без
прогонів, де такі випадки трапилися. Потім він друкує абсолютні різниці в наносекундах і розрив
ярусів по всіх прогонах. Параметр `--exclude` натомість задає вилучені прогони явно, наприклад
`--exclude 3,11`.

```sh
python3 multiplicity_ci.py data/campaign-4/campaign.json
```

Скрипт друкує бутстреп-інтервал медіанної кратності кожного класу відносно бази відліку поруч із
розмахом кратності.

Зерно ресемплінгу зафіксоване в `runner.py`, тож команди щоразу друкують ті самі числа. Вони
збігаються з розділами [Основні результати](data/campaign-4/REPORT.md#основні-результати) і
[Додаткові аналізи після даних](data/campaign-4/REPORT.md#додаткові-аналізи-після-даних) звіту
кампанії 4.

### Запуск кампанії

Для кампанії потрібні Linux із systemd на процесорі AMD або Intel архітектури x86-64, CPython 3.12
із заголовковими файлами, gcc і права root. На процесорах AMD `prepare_machine.sh` потребує ще
msr-tools. Команди запускаються з кореня репозиторію. Кожна кампанія має власну теку
`data/campaign-N`, яку `prepare_machine.sh` створює з наступним вільним номером. Туди записуються
всі файли кампанії, крім зібраних представників, які лишаються в корені репозиторію.

Кампанія виконується за протоколом, написаним до її першого прогону. Протокол нової кампанії
записується у файл `PROTOCOL.md` у теці кампанії. Без цього файлу `run_campaign.sh` не
запускається, а `runner.py` зберігає його контрольну суму разом з результатами. Текст протоколу
опублікованих кампаній до репозиторію не входить.

#### 1. Підготовка машини

Увійдіть у текстову консоль, наприклад через Ctrl+Alt+F3, бо скрипт зупиняє графічний сеанс, і
виконайте

```sh
sudo ./prepare_machine.sh 2
```

Аргумент задає вимірювальне ядро, у цих прикладах ядро 2. Годиться будь-яке ввімкнене ядро, крім
ядра 0. Без аргументу скрипт бере ядро з найбільшим номером.

Скрипт перевіряє живлення від мережі, зупиняє графічний сеанс і фонові служби, перевіряє, що не
працюють браузер і менеджер пакетів, вимикає одночасну багатопотоковість і прискорення частоти,
встановлює регулятор частоти `performance` з фіксованою частотою і відводить переривання на ядро 0.
Потім він чекає, доки середнє навантаження не впаде нижче 0,5, навантажує вимірювальне ядро і
перевіряє, що під навантаженням воно тримає частоту. Частотою стає найвища з тих, які пропонує
драйвер, або наступна нижча, якщо під навантаженням ядро її перевищує. Частоту в кГц можна задати й
явно:

```sh
sudo FREQ_KHZ=1600000 ./prepare_machine.sh 2
```

Після перевірки передумов скрипт створює теку кампанії, а наприкінці друкує її назву. Теку, що
лишилася від попередньої спроби і ще не містить результатів, скрипт використовує повторно. На
першому невдалому кроці скрипт зупиняється. Стан машини, зокрема невдалий крок, записується в
`machine_state.txt` у теці кампанії, а `runner.py` зберігає контрольну суму цього файлу разом з
результатами. Налаштування діють до перезавантаження. Кроки відповідають
[розділу 6](data/campaign-4/PROTOCOL.md#6-середовище) протоколу кампанії 4.

#### 2. Збірка представників

Від імені звичайного користувача:

```sh
./run_campaign.sh 2 build
```

Скрипт збирає з `probe.c` модуль `probe_full.so` із загальним публічним C API і модуль
`probe_limited.so` з `Py_LIMITED_API` та записує параметри збірки в `probe_build.json` у теці
кампанії. Потім він перевіряє, що обидва представники правильно додають, віддають посилання на свій
тип і мають гарячі функції, вирівняні на 64 байти. Збірка є окремою командою, щоб компіляція ніколи
не йшла безпосередньо перед вимірюванням.

#### 3. Вимірювання

```sh
./run_campaign.sh 2
```

Спершу скрипт перевіряє, що зібрані модулі досі відповідають `probe.c` та інтерпретатору. Потім він
виконує димовий тест і пілотне дослідження прив'язки, а перед кампанією з 18 прогонів просить
підтвердження. Наприкінці кампанії `runner.py` друкує аналіз нових даних, зафіксований наперед.
Результати записуються в `smoke.json`, `pilot.pinned.json`, `pilot.free.json` і `campaign.json` у
теці кампанії. Файл `smoke.json` є перевіркою працездатності. `run_campaign.sh` бере теку кампанії з
найбільшим номером і відмовляється писати в теку, де вже є `campaign.json`.

Етапи можна запускати й окремо, як `./run_campaign.sh 2 smoke`, `pilot` або `campaign`. Кожен
запуск зберігає наявні файли результатів під іменами з позначкою часу, зокрема файли попереднього
етапу.

| Змінна | Призначення | Типово |
|---|---|---|
| `CAMPAIGN_DIR` | тека кампанії | `data/campaign-N` з найбільшим N |
| `PY` | шлях до інтерпретатора CPython 3.12 | перший знайдений з `python3.12`, `/opt/python3.12/bin/python3.12` і `/usr/bin/python3.12` |
| `RUNS` | кількість прогонів кампанії | 18 |
| `YES` | `1` продовжує після пілотного дослідження без запитання | запитувати |
| `PYTHONHASHSEED` | зерно хешування | 0 |

Після кампанії машину слід перезавантажити, щоб повернути її налаштування.

#### Повтор порядку прогонів

Порядок прогонів перемішується із зерном, записаним у поле `design.row_seed` файлу
`campaign.json`. Щоб повторити порядок опублікованої кампанії, зберіть представників і викличте
`runner.py` напряму з теки кампанії з цим зерном замість `SEED`:

```sh
cd data/campaign-N
PYTHONHASHSEED=0 python3.12 ../../runner.py --core 2 --runs 18 --seed SEED --out campaign.json
```
