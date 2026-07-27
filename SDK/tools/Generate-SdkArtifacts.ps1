param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$sdkRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $sdkRoot '..'))
$addressPath = Join-Path $sdkRoot 'address-catalog.json'
$routePath = Join-Path $sdkRoot 'mission-routes.json'

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
        $lines.Add(('    {{{0}, {1}, "{2}", "{3}", {4}, {5}, "{6}"}},' -f
            $route.selector_level,
            $route.engine_mission,
            (Escape-CppString ([string]$route.id)),
            (Escape-CppString ([string]$route.vwf_name)),
            $(if ([bool]$route.requires_file) { 'true' } else { 'false' }),
            $redirectRva,
            (Escape-CppString $redirectExpected)))
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
    $lines.Add('        public M1937MissionRoute(int selectorLevel, int engineMission, string id, string vwfName, bool requiresFile, long redirectRva, string redirectExpected)')
    $lines.Add('        {')
    $lines.Add('            SelectorLevel = selectorLevel;')
    $lines.Add('            EngineMission = engineMission;')
    $lines.Add('            Id = id;')
    $lines.Add('            VwfName = vwfName;')
    $lines.Add('            RequiresFile = requiresFile;')
    $lines.Add('            RedirectRva = redirectRva;')
    $lines.Add('            RedirectExpected = redirectExpected;')
    $lines.Add('        }')
    $lines.Add('        public int SelectorLevel { get; private set; }')
    $lines.Add('        public int EngineMission { get; private set; }')
    $lines.Add('        public string Id { get; private set; }')
    $lines.Add('        public string VwfName { get; private set; }')
    $lines.Add('        public bool RequiresFile { get; private set; }')
    $lines.Add('        public long RedirectRva { get; private set; }')
    $lines.Add('        public string RedirectExpected { get; private set; }')
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
        $lines.Add(('            new M1937MissionRoute({0}, {1}, "{2}", "{3}", {4}, {5}L, "{6}"),' -f
            $route.selector_level,
            $route.engine_mission,
            (Escape-CppString ([string]$route.id)),
            (Escape-CppString ([string]$route.vwf_name)),
            $(if ([bool]$route.requires_file) { 'true' } else { 'false' }),
            $redirectRva,
            (Escape-CppString $redirectExpected)))
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
            [pscustomobject]$entry
        })
    }
    return ($catalog | ConvertTo-Json -Depth 8)
}

$addressCatalog = Get-Content -LiteralPath $addressPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$routeCatalog = Get-Content -LiteralPath $routePath -Raw -Encoding UTF8 |
    ConvertFrom-Json

$duplicateNames = $addressCatalog.addresses |
    Group-Object name | Where-Object Count -gt 1
$duplicateRvas = $addressCatalog.addresses |
    Group-Object { Format-Rva ([string]$_.rva) } |
    Where-Object Count -gt 1
if ($duplicateNames -or $duplicateRvas) {
    throw 'Address catalog contains duplicate names or RVAs.'
}
$levels = @($routeCatalog.routes | ForEach-Object { [int]$_.selector_level })
if (($levels | Sort-Object -Unique).Count -ne $levels.Count -or
    ($levels | Measure-Object -Minimum).Minimum -ne 1 -or
    ($levels | Measure-Object -Maximum).Maximum -ne $levels.Count) {
    throw 'Mission selector levels must be unique and contiguous from 1.'
}

$selectorDirectory = Join-Path $repositoryRoot 'Patch\src\level-selector'
$selectorPath = Join-Path $selectorDirectory (
    [string]$routeCatalog.selector_output)

$outputs = [ordered]@{
    (Join-Path $sdkRoot 'include\M1937SDK\Addresses.hpp') =
        New-AddressHeader $addressCatalog
    (Join-Path $sdkRoot 'generated\M1937Addresses.cs') =
        New-CSharpAddresses $addressCatalog
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
    if ($actual -ceq $expected) { continue }
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
