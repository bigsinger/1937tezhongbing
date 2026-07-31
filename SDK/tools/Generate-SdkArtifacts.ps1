param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$sdkRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $sdkRoot '..'))
$addressPath = Join-Path $sdkRoot 'address-catalog.json'
$routePath = Join-Path $sdkRoot 'mission-routes.json'
$crtRandPath = Join-Path $sdkRoot 'crt-rand-call-sites.json'

function Convert-ToSnakeCase {
    param([Parameter(Mandatory)][string]$Name)
    $value = [regex]::Replace($Name, '([a-z0-9])([A-Z])', '$1_$2')
    $value = [regex]::Replace($value, '([A-Za-z])([0-9])', '$1_$2')
    $value = [regex]::Replace($value, '([0-9])([A-Za-z])', '$1_$2')
    return $value.ToLowerInvariant()
}

function Format-Rva {
    param([Parameter(Mandatory)][string]$Value)
    return ('0x{0:X8}' -f [Convert]::ToUInt32(
        $Value.Substring(2), 16))
}

function Escape-CppString {
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { return '' }
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function New-AddressHeader {
    param($Catalog)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('#pragma once')
    $lines.Add('')
    $lines.Add('// Generated from SDK/address-catalog.json. Do not edit.')
    $lines.Add('#include <cstddef>')
    $lines.Add('#include <cstdint>')
    $lines.Add('')
    $lines.Add('namespace m1937::sdk {')
    $lines.Add('')
    $lines.Add('struct ExecutableIdentity final {')
    $lines.Add(('    static constexpr std::uint32_t preferred_image_base = {0};' -f $Catalog.supported_executable.preferred_image_base))
    $lines.Add(('    static constexpr std::uint32_t image_size = {0};' -f $Catalog.supported_executable.size_of_image))
    $lines.Add(('    static constexpr std::uint32_t pe_timestamp = {0};' -f $Catalog.supported_executable.pe_timestamp))
    $lines.Add(('    static constexpr std::uint32_t entry_point_rva = {0};' -f $Catalog.supported_executable.entry_point_rva))
    $lines.Add(('    static constexpr std::size_t file_size = {0};' -f ([string]$Catalog.supported_executable.file_size)))
    $lines.Add(('    static constexpr const char* sha256 = "{0}";' -f $Catalog.supported_executable.sha256))
    $lines.Add('};')
    $lines.Add('')
    $lines.Add('namespace rva {')
    foreach ($address in $Catalog.addresses) {
        $name = Convert-ToSnakeCase ([string]$address.name)
        $lines.Add(('inline constexpr std::uintptr_t {0} = {1};' -f $name, (Format-Rva ([string]$address.rva))))
    }
    $lines.Add('')
    $lines.Add('}  // namespace rva')
    $lines.Add('}  // namespace m1937::sdk')
    $lines.Add('')
    return [string]::Join("`n", $lines)
}

function New-CSharpAddresses {
    param($Catalog)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('// Generated from SDK/address-catalog.json. Do not edit.')
    $lines.Add('namespace Mission1937.SDK.Generated')
    $lines.Add('{')
    $lines.Add('    public static class M1937ExecutableIdentity')
    $lines.Add('    {')
    $lines.Add(('        public const string Sha256 = "{0}";' -f $Catalog.supported_executable.sha256))
    $lines.Add(('        public const long FileSize = {0}L;' -f ([string]$Catalog.supported_executable.file_size)))
    $lines.Add(('        public const long PreferredImageBase = {0}L;' -f $Catalog.supported_executable.preferred_image_base))
    $lines.Add(('        public const long SizeOfImage = {0}L;' -f $Catalog.supported_executable.size_of_image))
    $lines.Add(('        public const long PeTimestamp = {0}L;' -f $Catalog.supported_executable.pe_timestamp))
    $lines.Add(('        public const long EntryPointRva = {0}L;' -f $Catalog.supported_executable.entry_point_rva))
    $lines.Add('    }')
    $lines.Add('')
    $lines.Add('    public static class M1937Addresses')
    $lines.Add('    {')
    foreach ($address in $Catalog.addresses) {
        $lines.Add(('        public const long {0} = {1}L;' -f $address.name, (Format-Rva ([string]$address.rva))))
    }
    $lines.Add('    }')
    $lines.Add('}')
    $lines.Add('')
    return [string]::Join("`n", $lines)
}

function New-CrtRandomHeader {
    param($Catalog)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('#pragma once')
    $lines.Add('')
    $lines.Add('// Generated from SDK/crt-rand-call-sites.json. Do not edit.')
    $lines.Add('#include <cstddef>')
    $lines.Add('#include <cstdint>')
    $lines.Add('')
    $lines.Add('namespace m1937::sdk::crt_random {')
    $lines.Add('')
    $lines.Add('inline constexpr std::uint32_t initial_state = 1;')
    $lines.Add('')
    $lines.Add('constexpr std::uint32_t step(std::uint32_t state) noexcept {')
    $lines.Add('    return state * 214013u + 2531011u;')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add('constexpr std::uint16_t value(std::uint32_t state_after_step) noexcept {')
    $lines.Add('    return static_cast<std::uint16_t>(')
    $lines.Add('        (state_after_step >> 16u) & 0x7fffu);')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add('struct CallSite final {')
    $lines.Add('    std::uintptr_t rva;')
    $lines.Add('    std::uintptr_t caller_rva;')
    $lines.Add('    const char* engine_symbol;')
    $lines.Add('    const char* semantic_name;')
    $lines.Add('    const char* domain;')
    $lines.Add('    const char* purpose;')
    $lines.Add('    const char* confidence;')
    $lines.Add('    bool formal_missions;')
    $lines.Add('};')
    $lines.Add('')
    $lines.Add('inline constexpr CallSite call_sites[] = {')
    foreach ($caller in $Catalog.callers) {
        foreach ($operation in $caller.operations) {
            foreach ($site in $operation.sites) {
                $lines.Add(('    {{{0}, {1}, "{2}", "{3}", "{4}", "{5}", "{6}", {7}}},' -f
                    (Format-Rva ([string]$site)),
                    (Format-Rva ([string]$caller.caller_rva)),
                    (Escape-CppString ([string]$caller.engine_symbol)),
                    (Escape-CppString ([string]$caller.semantic_name)),
                    (Escape-CppString ([string]$caller.domain)),
                    (Escape-CppString ([string]$operation.purpose)),
                    (Escape-CppString ([string]$caller.confidence)),
                    $(if ([bool]$caller.formal_missions) {
                        'true'
                    } else {
                        'false'
                    })))
            }
        }
    }
    $lines.Add('};')
    $lines.Add('')
    $lines.Add('inline constexpr std::size_t call_site_count =')
    $lines.Add('    sizeof(call_sites) / sizeof(call_sites[0]);')
    $lines.Add('')
    $lines.Add('constexpr const CallSite* find_call_site(')
    $lines.Add('    std::uintptr_t rva) noexcept {')
    $lines.Add('    for (const auto& site : call_sites) {')
    $lines.Add('        if (site.rva == rva)')
    $lines.Add('            return &site;')
    $lines.Add('    }')
    $lines.Add('    return nullptr;')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add('}  // namespace m1937::sdk::crt_random')
    $lines.Add('')
    return [string]::Join("`n", $lines)
}

function New-GdscriptCrtRandomCatalog {
    param($Catalog)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# Generated from SDK/crt-rand-call-sites.json. Do not edit.')
    $lines.Add('class_name LegacyCrtRandomCatalog')
    $lines.Add('extends RefCounted')
    $lines.Add('')
    $lines.Add('const INITIAL_STATE := 1')
    $lines.Add(('const CALL_SITE_COUNT := {0}' -f
        [int]$Catalog.direct_call_site_count))
    $lines.Add('const UINT32_MASK := 0xffffffff')
    $lines.Add('const OUTPUT_MASK := 0x7fff')
    $lines.Add('')
    $lines.Add('const CALL_SITES := {')
    foreach ($caller in $Catalog.callers) {
        foreach ($operation in $caller.operations) {
            foreach ($site in $operation.sites) {
                $lines.Add(('    {0}: {{' -f
                    (Format-Rva ([string]$site))))
                $lines.Add(('        "caller_rva": {0},' -f
                    (Format-Rva ([string]$caller.caller_rva))))
                $lines.Add(('        "engine_symbol": "{0}",' -f
                    (Escape-CppString ([string]$caller.engine_symbol))))
                $lines.Add(('        "semantic_name": "{0}",' -f
                    (Escape-CppString ([string]$caller.semantic_name))))
                $lines.Add(('        "domain": "{0}",' -f
                    (Escape-CppString ([string]$caller.domain))))
                $lines.Add(('        "purpose": "{0}",' -f
                    (Escape-CppString ([string]$operation.purpose))))
                $lines.Add(('        "formal_missions": {0},' -f
                    $(if ([bool]$caller.formal_missions) {
                        'true'
                    } else {
                        'false'
                    })))
                $lines.Add('    },')
            }
        }
    }
    $lines.Add('}')
    $lines.Add('')
    $lines.Add('')
    $lines.Add('static func next_state(state: int) -> int:')
    $lines.Add('    return int((state * 214013 + 2531011) & UINT32_MASK)')
    $lines.Add('')
    $lines.Add('')
    $lines.Add('static func random_value(state_after_step: int) -> int:')
    $lines.Add('    return int((state_after_step >> 16) & OUTPUT_MASK)')
    $lines.Add('')
    $lines.Add('')
    $lines.Add('static func metadata_for_rva(rva: int) -> Dictionary:')
    $lines.Add('    var value: Variant = CALL_SITES.get(rva)')
    $lines.Add('    return (')
    $lines.Add('        (value as Dictionary).duplicate(true)')
    $lines.Add('        if value is Dictionary')
    $lines.Add('        else {}')
    $lines.Add('    )')
    $lines.Add('')
    $lines.Add('')
    $lines.Add('static func rvas_for_operation(')
    $lines.Add('    semantic_name: String,')
    $lines.Add('    purpose: String,')
    $lines.Add(') -> Array[int]:')
    $lines.Add('    var result: Array[int] = []')
    $lines.Add('    for raw_rva: Variant in CALL_SITES:')
    $lines.Add('        var rva := int(raw_rva)')
    $lines.Add('        var metadata := CALL_SITES[rva] as Dictionary')
    $lines.Add('        if (')
    $lines.Add('            str(metadata.get("semantic_name", "")) == semantic_name')
    $lines.Add('            and str(metadata.get("purpose", "")) == purpose')
    $lines.Add('        ):')
    $lines.Add('            result.append(rva)')
    $lines.Add('    result.sort()')
    $lines.Add('    return result')
    $lines.Add('')
    return [string]::Join("`n", $lines)
}

function New-MissionHeader {
    param($RouteCatalog, $AddressCatalog)
    $addresses = @{}
    foreach ($address in $AddressCatalog.addresses) {
        $addresses[[string]$address.name] = Format-Rva ([string]$address.rva)
    }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('#pragma once')
    $lines.Add('')
    $lines.Add('// Generated from SDK/mission-routes.json. Do not edit.')
    $lines.Add('#include <cstddef>')
    $lines.Add('#include <cstdint>')
    $lines.Add('')
    $lines.Add('namespace m1937::sdk {')
    $lines.Add('')
    $lines.Add('struct MissionRoute final {')
    $lines.Add('    int selector_level;')
    $lines.Add('    int engine_mission;')
    $lines.Add('    const char* id;')
    $lines.Add('    const char* vwf_name;')
    $lines.Add('    bool requires_file;')
    $lines.Add('    std::uintptr_t redirect_rva;')
    $lines.Add('    const char* redirect_expected;')
    $lines.Add('    const wchar_t* title;')
    $lines.Add('    const wchar_t* briefing;')
    $lines.Add('    const wchar_t* objective_1;')
    $lines.Add('    const wchar_t* objective_2;')
    $lines.Add('    const wchar_t* objective_3;')
    $lines.Add('    bool replace_legacy_briefing;')
    $lines.Add('};')
    $lines.Add('')
    $lines.Add('inline constexpr MissionRoute mission_routes[] = {')
    foreach ($route in $RouteCatalog.routes) {
        $redirectRva = '0'
        $redirectExpected = ''
        if ($route.PSObject.Properties.Name -contains 'redirect_address') {
            $redirectName = [string]$route.redirect_address
            if (-not $addresses.ContainsKey($redirectName)) {
                throw "Mission route references unknown address: $redirectName"
            }
            $redirectRva = $addresses[$redirectName]
            $redirectExpected = [string]$route.redirect_expected
            if ($redirectExpected.Length -ne ([string]$route.vwf_name).Length) {
                throw "Mission route $($route.selector_level) changes the fixed VWF string length."
            }
        }
        $objectives = @($route.objectives)
        $lines.Add(('    {{{0}, {1}, "{2}", "{3}", {4}, {5}, "{6}", L"{7}", L"{8}", L"{9}", L"{10}", L"{11}", {12}}},' -f
            $route.selector_level,
            $route.engine_mission,
            (Escape-CppString ([string]$route.id)),
            (Escape-CppString ([string]$route.vwf_name)),
            $(if ([bool]$route.requires_file) { 'true' } else { 'false' }),
            $redirectRva,
            (Escape-CppString $redirectExpected),
            (Escape-CppString ([string]$route.title)),
            (Escape-CppString ([string]$route.briefing)),
            (Escape-CppString ([string]$objectives[0])),
            (Escape-CppString ([string]$objectives[1])),
            (Escape-CppString ([string]$objectives[2])),
            $(if ([bool]$route.replace_legacy_briefing) {
                'true'
            } else {
                'false'
            })))
    }
    $lines.Add('};')
    $lines.Add('')
    $lines.Add('inline constexpr std::size_t mission_route_count =')
    $lines.Add('    sizeof(mission_routes) / sizeof(mission_routes[0]);')
    $lines.Add('')
    $lines.Add('inline constexpr const MissionRoute* find_mission_route(int selector_level) {')
    $lines.Add('    for (const auto& route : mission_routes) {')
    $lines.Add('        if (route.selector_level == selector_level)')
    $lines.Add('            return &route;')
    $lines.Add('    }')
    $lines.Add('    return nullptr;')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add('}  // namespace m1937::sdk')
    $lines.Add('')
    return [string]::Join("`n", $lines)
}

function New-CSharpMissionRoutes {
    param($RouteCatalog, $AddressCatalog)
    $addresses = @{}
    foreach ($address in $AddressCatalog.addresses) {
        $addresses[[string]$address.name] =
            Format-Rva ([string]$address.rva)
    }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('// Generated from SDK/mission-routes.json. Do not edit.')
    $lines.Add('namespace Mission1937.SDK.Generated')
    $lines.Add('{')
    $lines.Add('    public sealed class M1937MissionRoute')
    $lines.Add('    {')
    $lines.Add('        public M1937MissionRoute(int selectorLevel, int engineMission, string id, string vwfName, bool requiresFile, long redirectRva, string redirectExpected, string title, string briefing, string[] objectives, bool replaceLegacyBriefing)')
    $lines.Add('        {')
    $lines.Add('            SelectorLevel = selectorLevel;')
    $lines.Add('            EngineMission = engineMission;')
    $lines.Add('            Id = id;')
    $lines.Add('            VwfName = vwfName;')
    $lines.Add('            RequiresFile = requiresFile;')
    $lines.Add('            RedirectRva = redirectRva;')
    $lines.Add('            RedirectExpected = redirectExpected;')
    $lines.Add('            Title = title;')
    $lines.Add('            Briefing = briefing;')
    $lines.Add('            Objectives = objectives;')
    $lines.Add('            ReplaceLegacyBriefing = replaceLegacyBriefing;')
    $lines.Add('        }')
    $lines.Add('        public int SelectorLevel { get; private set; }')
    $lines.Add('        public int EngineMission { get; private set; }')
    $lines.Add('        public string Id { get; private set; }')
    $lines.Add('        public string VwfName { get; private set; }')
    $lines.Add('        public bool RequiresFile { get; private set; }')
    $lines.Add('        public long RedirectRva { get; private set; }')
    $lines.Add('        public string RedirectExpected { get; private set; }')
    $lines.Add('        public string Title { get; private set; }')
    $lines.Add('        public string Briefing { get; private set; }')
    $lines.Add('        public string[] Objectives { get; private set; }')
    $lines.Add('        public bool ReplaceLegacyBriefing { get; private set; }')
    $lines.Add('    }')
    $lines.Add('')
    $lines.Add('    public static class M1937MissionRoutes')
    $lines.Add('    {')
    $lines.Add('        public static readonly M1937MissionRoute[] All =')
    $lines.Add('        {')
    foreach ($route in $RouteCatalog.routes) {
        $redirectRva = '0'
        $redirectExpected = ''
        if ($route.PSObject.Properties.Name -contains 'redirect_address') {
            $redirectName = [string]$route.redirect_address
            $redirectRva = $addresses[$redirectName]
            $redirectExpected = [string]$route.redirect_expected
        }
        $objectives = @($route.objectives)
        $lines.Add(('            new M1937MissionRoute({0}, {1}, "{2}", "{3}", {4}, {5}L, "{6}", "{7}", "{8}", new[] {{ "{9}", "{10}", "{11}" }}, {12}),' -f
            $route.selector_level,
            $route.engine_mission,
            (Escape-CppString ([string]$route.id)),
            (Escape-CppString ([string]$route.vwf_name)),
            $(if ([bool]$route.requires_file) { 'true' } else { 'false' }),
            $redirectRva,
            (Escape-CppString $redirectExpected),
            (Escape-CppString ([string]$route.title)),
            (Escape-CppString ([string]$route.briefing)),
            (Escape-CppString ([string]$objectives[0])),
            (Escape-CppString ([string]$objectives[1])),
            (Escape-CppString ([string]$objectives[2])),
            $(if ([bool]$route.replace_legacy_briefing) {
                'true'
            } else {
                'false'
            })))
    }
    $lines.Add('        };')
    $lines.Add('')
    $lines.Add('        public static M1937MissionRoute Find(int selectorLevel)')
    $lines.Add('        {')
    $lines.Add('            foreach (M1937MissionRoute route in All)')
    $lines.Add('            {')
    $lines.Add('                if (route.SelectorLevel == selectorLevel)')
    $lines.Add('                    return route;')
    $lines.Add('            }')
    $lines.Add('            return null;')
    $lines.Add('        }')
    $lines.Add('    }')
    $lines.Add('}')
    $lines.Add('')
    return [string]::Join("`n", $lines)
}

function New-SelectorCatalog {
    param($RouteCatalog)
    $catalog = [ordered]@{
        window_title = [string]$RouteCatalog.selector_ui.window_title
        heading = [string]$RouteCatalog.selector_ui.heading
        hint = [string]$RouteCatalog.selector_ui.hint
        missing_executable =
            [string]$RouteCatalog.selector_ui.missing_executable
        launch_failed = [string]$RouteCatalog.selector_ui.launch_failed
        cancel = [string]$RouteCatalog.selector_ui.cancel
        button_template = [string]$RouteCatalog.selector_ui.button_template
        missions = @($RouteCatalog.routes | ForEach-Object {
            $entry = [ordered]@{
                number = [int]$_.selector_level
                engine_mission = [int]$_.engine_mission
                id = [string]$_.id
                title = [string]$_.title
                vwf_name = [string]$_.vwf_name
                requires_file = [bool]$_.requires_file
                is_extension = [int]$_.selector_level -gt 12
            }
            if ($_.PSObject.Properties.Name -contains 'briefing') {
                $entry.briefing = [string]$_.briefing
            }
            if ($_.PSObject.Properties.Name -contains 'objectives') {
                $entry.objectives = @(
                    $_.objectives | ForEach-Object { [string]$_ })
            }
            if ($_.PSObject.Properties.Name -contains
                'replace_legacy_briefing') {
                $entry.replace_legacy_briefing =
                    [bool]$_.replace_legacy_briefing
            }
            [pscustomobject]$entry
        })
    }
    return ($catalog | ConvertTo-Json -Depth 8)
}

$addressCatalog = Get-Content -LiteralPath $addressPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$routeCatalog = Get-Content -LiteralPath $routePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$crtRandCatalog =
    Get-Content -LiteralPath $crtRandPath -Raw -Encoding UTF8 |
    ConvertFrom-Json

$duplicateNames = $addressCatalog.addresses |
    Group-Object name | Where-Object Count -gt 1
$duplicateRvas = $addressCatalog.addresses |
    Group-Object { Format-Rva ([string]$_.rva) } |
    Where-Object Count -gt 1
if ($duplicateNames -or $duplicateRvas) {
    throw 'Address catalog contains duplicate names or RVAs.'
}
$crtRandSites = @(
    $crtRandCatalog.callers | ForEach-Object {
        $_.operations | ForEach-Object { $_.sites }
    })
$duplicateCrtRandSites = $crtRandSites |
    Group-Object { Format-Rva ([string]$_) } |
    Where-Object Count -gt 1
if ($duplicateCrtRandSites -or
    $crtRandSites.Count -ne [int]$crtRandCatalog.direct_call_site_count) {
    throw (
        'CRT rand catalog site count does not match its unique direct ' +
        'call-site entries.')
}
if ([string]$crtRandCatalog.supported_executable_sha256 -cne
    [string]$addressCatalog.supported_executable.sha256) {
    throw 'CRT rand catalog targets a different executable identity.'
}
$levels = @($routeCatalog.routes | ForEach-Object { [int]$_.selector_level })
if (($levels | Sort-Object -Unique).Count -ne $levels.Count -or
    ($levels | Measure-Object -Minimum).Minimum -ne 1 -or
    ($levels | Measure-Object -Maximum).Maximum -ne $levels.Count) {
    throw 'Mission selector levels must be unique and contiguous from 1.'
}
foreach ($route in $routeCatalog.routes) {
    if ([string]::IsNullOrWhiteSpace([string]$route.title) -or
        [string]::IsNullOrWhiteSpace([string]$route.briefing) -or
        @($route.objectives).Count -ne 3 -or
        @($route.objectives | Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_)
        }).Count -ne 0 -or
        -not [bool]$route.replace_legacy_briefing) {
        throw (
            "Mission route $($route.selector_level) must define a title, " +
            'briefing, exactly three objectives, and enable the in-game ' +
            'text briefing replacement.')
    }
}

$selectorDirectory = Join-Path $repositoryRoot 'Patch\src\level-selector'
$selectorPath = Join-Path $selectorDirectory (
    [string]$routeCatalog.selector_output)

$outputs = [ordered]@{
    (Join-Path $sdkRoot 'include\M1937SDK\Addresses.hpp') =
        New-AddressHeader $addressCatalog
    (Join-Path $sdkRoot 'generated\M1937Addresses.cs') =
        New-CSharpAddresses $addressCatalog
    (Join-Path $sdkRoot 'include\M1937SDK\CrtRandom.hpp') =
        New-CrtRandomHeader $crtRandCatalog
    (Join-Path $repositoryRoot (
        'Remake\game\scripts\generated\legacy_crt_random_catalog.gd')) =
        New-GdscriptCrtRandomCatalog $crtRandCatalog
    (Join-Path $sdkRoot 'include\M1937SDK\MissionRoutes.hpp') =
        New-MissionHeader $routeCatalog $addressCatalog
    (Join-Path $sdkRoot 'generated\M1937MissionRoutes.cs') =
        New-CSharpMissionRoutes $routeCatalog $addressCatalog
    $selectorPath = New-SelectorCatalog $routeCatalog
}

$changed = @()
foreach ($entry in $outputs.GetEnumerator()) {
    $expected = $entry.Value.Replace("`r`n", "`n")
    $actual = if (Test-Path -LiteralPath $entry.Key -PathType Leaf) {
        [IO.File]::ReadAllText($entry.Key, [Text.Encoding]::UTF8).
            Replace("`r`n", "`n")
    } else {
        ''
    }
    $matches = $actual -ceq $expected
    if ($Check -and -not $matches -and
        [IO.Path]::GetExtension($entry.Key) -eq '.json') {
        try {
            # ConvertTo-Json indentation differs between Windows PowerShell
            # 5.1 and PowerShell 7. Compare generated JSON semantically so a
            # clean checkout passes on both runtimes while value/order drift
            # is still rejected by the single-source guard.
            $expectedCompact = $expected | ConvertFrom-Json |
                ConvertTo-Json -Depth 16 -Compress
            $actualCompact = $actual | ConvertFrom-Json |
                ConvertTo-Json -Depth 16 -Compress
            $matches = $actualCompact -ceq $expectedCompact
        }
        catch {
            $matches = $false
        }
    }
    if ($matches) { continue }
    $changed += $entry.Key.Substring($repositoryRoot.Length).TrimStart('\')
    if (-not $Check) {
        $directory = Split-Path -Parent $entry.Key
        [IO.Directory]::CreateDirectory($directory) | Out-Null
        [IO.File]::WriteAllText(
            $entry.Key, $entry.Value, [Text.UTF8Encoding]::new($false))
    }
}

if ($Check -and $changed.Count -gt 0) {
    throw "Generated SDK artifacts are stale: $($changed -join ', ')"
}
if ($Check) {
    Write-Host 'SDK generated artifacts are current.'
} else {
    Write-Host "Generated $($outputs.Count) SDK artifacts."
}
