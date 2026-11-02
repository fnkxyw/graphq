<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/banner-dark.png">
    <img src="docs/banner-light.png" alt="graphq — a hand-drawn whiteboard for your Mac">
  </picture>
</p>

<p align="center">
  Схемы, диаграммы и наброски в стиле «от руки».<br>
  Нативное macOS-приложение: без браузера, аккаунтов и облака.
</p>

<p align="center">
  <a href="https://github.com/fnkxyw/graphq/releases/latest"><b>Скачать для macOS</b></a>
  &nbsp;·&nbsp;
  <a href="#возможности">Возможности</a>
  &nbsp;·&nbsp;
  <a href="#горячие-клавиши">Горячие клавиши</a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/demo-dark.gif">
    <img src="docs/demo-light.gif" width="760" alt="Рисуем фигуры, соединяем стрелками, двигаем — стрелки едут следом">
  </picture>
</p>

## Установка

1. Скачайте `graphq.dmg` со страницы [Releases](https://github.com/fnkxyw/graphq/releases/latest).
2. Перетащите **graphq** в **Applications**.
3. Запустите из Launchpad или Spotlight.

macOS 14 Sonoma или новее.

> [!NOTE]
> graphq пока не нотаризован Apple, поэтому при первом запуске macOS его заблокирует.
> Откройте **Системные настройки → Конфиденциальность и безопасность** и нажмите **«Всё равно открыть»**,
> либо выполните в Терминале:
> ```sh
> xattr -dr com.apple.quarantine /Applications/graphq.app
> ```

<details>
<summary>Собрать из исходников</summary>

<br>

Нужен Xcode 16 или Command Line Tools.

```sh
git clone https://github.com/fnkxyw/graphq.git && cd graphq
make install
```

</details>

## Возможности

<table>
<tr>
<td width="50%" valign="top">

**Как на бумаге**<br>
Неровные линии, штриховка и рукописный шрифт. Три уровня «небрежности»: от аккуратного чертежа до мультяшного наброска.

</td>
<td width="50%" valign="top">

**Стрелки, которые не отваливаются**<br>
Стрелки цепляются к фигурам и следуют за ними. Бывают прямые, изогнутые и ломаные, с подписями прямо на линии.

</td>
</tr>
<tr>
<td valign="top">

**Карандаш с нажимом**<br>
Плавные линии переменной толщины. На графическом планшете учитывается сила нажатия пера.

</td>
<td valign="top">

**Экспорт куда угодно**<br>
PNG, SVG и PDF, светлый или тёмный вариант, с фоном или без. `⇧⌥⌘C` копирует выделение картинкой.

</td>
</tr>
<tr>
<td valign="top">

**Дружит с Excalidraw**<br>
Открывает `.excalidraw`-файлы как есть, те же горячие клавиши.

</td>
<td valign="top">

**Как настоящее Mac-приложение**<br>
Вкладки, автосохранение, история версий, тёмная тема. Тысячи фигур без лагов.

</td>
</tr>
</table>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
    <img src="docs/screenshot-light.png" width="760" alt="Окно graphq">
  </picture>
</p>

## Горячие клавиши

| | | | |
|:--|:--|:--|:--|
| `V` выделение | `R` прямоугольник | `O` эллипс | `D` ромб |
| `A` стрелка | `L` линия | `P` карандаш | `T` текст |
| `E` ластик | `H` рука | `Q` закрепить инструмент | `?` все сочетания |

Двойной клик по пустому месту создаёт текст, по фигуре или стрелке — подпись. `Space` + перетаскивание двигает холст, `⇧1` показывает всё.

---

<p align="center">
  <sub><a href="LICENSE">MIT</a> · шрифт Virgil под <a href="Sources/SketchRender/Resources/Fonts/OFL-Virgil.md">SIL OFL 1.1</a> · вдохновлено <a href="https://excalidraw.com">Excalidraw</a></sub>
</p>
