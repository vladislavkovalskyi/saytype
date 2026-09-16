import Foundation

/// English programming words as Russian speech and Whisper write them in Cyrillic:
/// "юзер" → user, "хендлер" → handler. Used after a casing trigger and around path
/// separators, never on ordinary text.
enum DeveloperVocabulary {
    struct Word: Sendable {
        let english: String
        /// Also an ordinary Russian word ("дата", "файл", "тест"). A weak "точка" never
        /// turns it into a path.
        let ambiguous: Bool
    }

    /// Normalized spelling (lowercase, ё and э as е) → word.
    static let words: [String: Word] = {
        var map: [String: Word] = [:]
        for line in table.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let english = parts[0].trimmingCharacters(in: .whitespaces)
            for spelling in parts[1].split(separator: " ") {
                let ambiguous = spelling.hasPrefix("*")
                let key = DeveloperText.normalize(String(spelling.drop { $0 == "*" }))
                map[key] = Word(english: english, ambiguous: ambiguous)
            }
        }
        return map
    }()

    /// Short words that join identifiers: "из лоадинг" → isLoading, "гет юзер бай айди" →
    /// getUserById. They count only when a vocabulary word follows.
    static let connectors: [String: String] = Dictionary(uniqueKeysWithValues: [
        "из": "is", "он": "on", "хэз": "has", "ту": "to", "бай": "by", "оф": "of", "фор": "for",
        "виз": "with", "уиз": "with", "фром": "from", "ин": "in", "эт": "at", "аут": "out", "ап": "up", "офф": "off",
    ].map { (DeveloperText.normalize($0.key), $0.value) })

    /// Connectors that are also Russian words; they never end a name: "юзер из дома".
    static let russianConnectors: Set<String> = ["из", "он", "ту"]

    /// Connectors that may start an identifier: isOpen, onClick, hasError.
    static let leadingConnectors: Set<String> = Set(["из", "он", "хэз", "is", "on", "has", "can", "should"].map(DeveloperText.normalize))

    static let latinConnectors: Set<String> = ["is", "on", "has", "can", "should", "to", "by", "of", "for", "with", "from", "in", "at", "as", "up", "out", "off"]

    /// English words that end an identifier and never act as operands: "camel case user data
    /// and then" stops before "and".
    static let latinStopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "so", "then", "than", "because", "if", "else", "when", "while",
        "that", "this", "these", "those", "which", "who", "what", "where", "how", "why",
        "it", "its", "i", "me", "my", "we", "us", "our", "you", "your", "he", "him", "his", "she", "her", "they", "them", "their",
        "is", "are", "was", "were", "be", "been", "being", "am", "do", "does", "did", "done",
        "have", "has", "had", "will", "would", "should", "could", "can", "may", "might", "must", "shall",
        "not", "no", "yes", "please", "also", "too", "very", "really", "just", "only", "even", "still",
        "here", "there", "now", "into", "onto", "instead", "about", "like", "more", "most", "less", "better", "best",
        "all", "any", "some", "each", "every", "other", "such", "same",
        "to", "of", "in", "on", "at", "by", "for", "with", "from", "as", "up", "out", "over", "under",
    ]

    /// english: spelling spelling *ambiguous-spelling
    private static let table = """
    user: юзер
    users: юзеры юзерс
    data: *дата дейта
    id: айди
    ids: айдишники айдис
    name: нейм
    names: неймы неймс
    list: *лист
    lists: листы листс
    state: стейт
    handler: хендлер
    handle: хендл хэндл
    handlers: хендлеры
    fetch: фетч
    fetcher: фетчер
    get: гет
    set: *сет
    post: *пост
    put: пут
    delete: делит дилит
    update: апдейт
    create: криейт креейт
    remove: ремув
    add: адд
    init: инит
    load: лоад лоуд
    loading: лоадинг лоудинг
    loaded: лоадед лоудед
    loader: лоадер лоудер
    save: сейв
    sign: сайн
    click: *клик
    submit: сабмит
    change: чейндж
    input: инпут
    output: аутпут
    button: баттон
    form: форм *форма
    modal: модал модалка
    header: хедер
    footer: футер
    sidebar: сайдбар
    navbar: навбар
    nav: нав
    layout: лейаут
    page: пейдж
    pages: пейджи пейджес
    component: *компонент
    components: компонентс *компоненты
    prop: проп
    props: пропс пропсы
    hook: *хук
    hooks: хукс *хуки
    context: *контекст
    provider: *провайдер
    store: стор
    reducer: редюсер редьюсер
    action: экшен экшн
    actions: экшены экшенс
    effect: *эффект
    use: юз
    memo: мемо
    ref: реф
    callback: колбек коллбек
    query: квери
    mutation: мутейшн *мутация
    router: *роутер
    route: роут
    routes: роуты роутс
    api: апи
    client: *клиент
    server: *сервер
    service: *сервис
    services: сервисы сервисез
    controller: *контроллер
    model: модел *модель
    models: моделс
    view: вью
    views: вьюс вьюхи
    config: конфиг
    configs: конфиги
    settings: сеттингс сеттинги
    option: опшен опшн
    options: опшенс опшнс
    utils: утилс ютилс *утилиты
    util: утил ютил
    helper: хелпер
    helpers: хелперы хелперс
    index: *индекс
    main: мейн
    app: апп эпп
    test: *тест
    tests: тестс *тесты
    spec: спек
    mock: мок
    mocks: моки мокс
    file: *файл
    files: *файлы файлс
    path: пэс
    url: урл юрл
    token: *токен
    tokens: токены
    auth: аус аутх ауф
    login: *логин
    logout: логаут
    password: пассворд пасворд
    email: имейл емейл мейл
    message: месседж меседж мессадж
    messages: месседжи месседжес
    chat: *чат
    error: эррор
    errors: эрроры
    response: респонс
    request: реквест
    result: резалт
    results: резалты
    value: валью вэлью
    values: вальюс вэльюс
    key: кей
    count: каунт
    counter: каунтер
    total: тотал
    item: айтем
    items: айтемы айтемс
    array: эррей эрей аррей
    object: обджект *объект
    string: стринг
    number: намбер
    boolean: булеан булин
    type: тайп
    types: тайпы тайпс
    interface: *интерфейс
    class: *класс
    function: фанкшн фанкшен *функция
    method: *метод
    variable: вериабл
    constant: констант
    default: дефолт
    event: ивент
    events: ивенты ивентс
    listener: листенер
    emit: эмит
    dispatch: диспатч
    subscribe: сабскрайб
    async: асинк
    await: эвейт
    promise: промис
    timeout: таймаут
    interval: *интервал
    date: дейт
    time: тайм
    start: *старт
    stop: *стоп
    end: энд
    open: опен оупен
    close: клоуз клоз
    closed: клоузд
    show: *шоу
    hide: хайд
    toggle: тоггл тогл
    visible: визибл
    enabled: энейблд инейблд
    disabled: дизейблд
    active: эктив *актив
    selected: селектед
    current: каррент куррент
    next: некст
    prev: прев
    previous: превиус
    first: ферст
    last: ласт
    new: нью
    old: олд
    all: олл
    find: файнд
    search: серч
    filter: филтер *фильтр
    sort: *сорт
    map: мап мэп
    reduce: редьюс
    parse: парс
    format: *формат
    render: *рендер
    mount: маунт
    unmount: анмаунт
    cache: *кэш
    storage: сторедж
    local: локал
    session: сешн *сессия
    cookie: *куки
    database: датабейс дейтабейс
    table: тейбл
    row: роу
    rows: роусы
    column: коламн
    schema: скима *схема
    migration: майгрейшн *миграция
    seed: сид
    comment: коммент
    comments: комменты комментс
    profile: профайл *профиль
    account: *аккаунт
    avatar: *аватар аватарка
    image: имидж имэдж
    images: имиджи
    icon: айкон *иконка
    title: тайтл
    text: *текст
    label: лейбл
    description: дескрипшн дескрипшен
    content: *контент
    body: боди
    container: *контейнер
    wrapper: враппер
    card: кард *карточка
    grid: грид
    link: линк
    links: линки
    menu: *меню
    tab: таб
    tabs: табы
    dropdown: дропдаун
    select: селект
    checkbox: чекбокс
    slider: *слайдер
    tooltip: тултип
    popup: попап
    dialog: *диалог
    toast: *тост
    alert: алерт
    notification: нотификейшн
    theme: *тема
    dark: дарк
    light: лайт
    color: колор
    style: стайл *стиль
    styles: стайлс *стили
    width: видс видт
    height: хайт
    size: сайз
    max: *макс
    min: *мин
    home: хоум
    dashboard: дашборд
    admin: *админ
    product: продакт
    products: продакты
    order: ордер
    orders: ордеры ордера
    cart: *карт
    price: прайс
    payment: пеймент
    checkout: чекаут
    customer: кастомер
    task: таск
    tasks: таски таскс
    todo: туду
    todos: тудушки тудус
    note: *ноут
    notes: ноутс
    project: проджект *проект
    team: тим
    member: мембер
    role: роул *роль
    permission: пермишн пермишен
    permissions: пермишены пермишнс
    job: джоб джоба
    queue: кью
    worker: воркер
    socket: *сокет
    stream: *стрим
    buffer: *буфер
    chunk: чанк
    chunks: чанки
    node: ноуд *нода
    graph: *граф
    edge: эдж
    root: рут
    parent: парент
    child: чайлд
    children: чилдрен
    element: *элемент
    document: *документ
    window: виндоу
    scroll: скролл скрол
    position: позишн
    offset: оффсет офсет
    length: ленгс ленгт
    empty: эмпти
    null: налл нулл
    undefined: андефайнд
    true: тру
    false: фолс
    valid: валид
    validate: валидейт
    validation: валидейшн *валидация
    check: *чек
    debug: дебаг
    log: *лог
    logs: логи
    logger: логгер
    warning: ворнинг
    info: инфо
    status: *статус
    code: *код
    version: вершн
    build: билд
    deploy: деплой
    release: *релиз
    env: энв
    dev: дев
    prod: прод
    remote: ремоут
    branch: бранч
    commit: коммит
    merge: мердж
    push: пуш
    pull: пулл
    hash: хэш
    secret: сикрет *секрет
    public: паблик
    private: прайват
    static: статик
    shared: шэред шейрд
    common: коммон
    core: кор
    base: бейс
    lib: либ
    libs: либы либс
    src: срц сорс
    assets: ассеты эссетс
    globals: глобалс
    docs: докс
    readme: ридми
    script: *скрипт
    scripts: *скрипты
    package: пэкедж пакадж *пакет
    packages: пакаджи
    module: *модуль
    modules: *модули
    plugin: *плагин
    plugins: плагины
    extension: экстеншн
    feature: *фича
    features: *фичи
    flag: *флаг
    flags: флаги
    manager: *менеджер
    builder: билдер
    factory: фактори
    adapter: *адаптер
    engine: энджин
    parser: парсер
    formatter: форматтер
    scanner: *сканер
    repository: репозиторий репо
    middleware: миддлвар мидлвар
    reader: ридер
    writer: райтер
    upload: аплоад
    uploader: аплоадер
    download: даунлоад
    import: *импорт
    export: *экспорт
    player: *плеер
    audio: *аудио
    video: *видео
    record: *рекорд
    recording: рекординг
    transcript: транскрипт
    word: ворд
    words: ворды
    language: ленгвидж
    mode: моуд *мод
    modes: *моды
    dictionary: диктионари
    term: терм
    terms: термы
    overlay: оверлей
    panel: *панель
    section: секшн *секция
    screen: *скрин
    screens: скрины
    step: степ
    steps: степы
    onboarding: онбординг
    history: хистори
    shortcut: шорткат
    hotkey: хоткей
    timer: *таймер
    delay: делей
    retry: ретрай
    retries: ретраи ретрайс
    limit: *лимит
    cursor: *курсор
    selection: селекшн
    field: филд
    fields: филды
    payload: пейлоад
    metadata: метадата
    headers: хедеры хедерс
    param: парам
    params: парамс парамы
    args: аргс
    unique: юник
    random: *рандом
    json: джейсон джсон
    sync: синк
    success: саксесс саксес
    failure: фейлюр
    pending: пендинг
    ready: реди
    mobile: мобайл
    desktop: *десктоп
    web: веб
    native: нейтив
    react: реакт
    python: пайтон *питон
    swift: свифт
    endpoint: эндпоинт эндпойнт
    webhook: вебхук
    frontend: фронтенд фронт
    backend: бэкенд бэк

    """
}

/// Casing and normalization shared by the developer rules.
enum DeveloperText {
    /// Lowercase with ё and э folded into е, so "Хэндлер" and "хендлер" meet.
    static func normalize(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x41...0x5A: out.append(Unicode.Scalar(scalar.value + 32)!)
            case 0x42D, 0x44D, 0x401, 0x451: out.append("е")
            case 0x410...0x42F: out.append(Unicode.Scalar(scalar.value + 32)!)
            default: out.append(scalar)
            }
        }
        return String(out)
    }

    static func isASCIILetter(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return (a >= 65 && a <= 90) || (a >= 97 && a <= 122)
    }

    static func isASCIIDigit(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return a >= 48 && a <= 57
    }

    /// "UserData", "user_data", "user-data", "HTTPServer" → lowercase parts.
    static func parts(of word: String) -> [String] {
        var parts: [String] = []
        var current = ""
        let chars = Array(word)
        for (i, c) in chars.enumerated() {
            guard isASCIILetter(c) || isASCIIDigit(c) else {
                if !current.isEmpty { parts.append(current) }
                current = ""
                continue
            }
            if !current.isEmpty, c.isUppercase {
                let prev = chars[i - 1]
                let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercase
                if prev.isLowercase || prev.isNumber || (prev.isUppercase && nextIsLower) {
                    parts.append(current)
                    current = ""
                }
            }
            current.append(c)
        }
        if !current.isEmpty { parts.append(current) }
        return parts.map { $0.lowercased() }
    }

    static func capitalized(_ part: String) -> String {
        guard let first = part.first else { return part }
        return first.uppercased() + part.dropFirst().lowercased()
    }
}
