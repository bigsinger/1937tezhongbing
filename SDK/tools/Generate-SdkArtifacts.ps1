param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$sdkRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $sdkRoot '..'))
$addressPath = Join-Path $sdkRoot 'address-catalog.json'
$routePath = Join-Path $sdkRoot 'mission-routes.json'
$crtRandPath = Join-Path $sdkRoot 'crt-rand-call-sites.json'
$soundPath = Join-Path $sdkRoot 'sound-routes.json'
$mediaPath = Join-Path $sdkRoot 'media-routes.json'

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

function Escape-GdString {
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { return '' }
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Format-IntegerArray {
    param($Values)
    return (@($Values | ForEach-Object { [string][int]$_ }) -join ', ')
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

function New-SoundHeader {
    param($Catalog)
    $sprite = @($Catalog.routes.sprite_group.unique_slf_indices)
    $voice = @($Catalog.routes.actor_voice.unique_slf_indices)
    $reachable = @($Catalog.reachable_zero_based_indices)
    $assetOnly = @($Catalog.asset_only_zero_based_indices)
    $environment = @($Catalog.audited_environment_and_ui_entries)
    $uiButtonEntry = @($environment | Where-Object {
        [int]$_.zero_based_index -eq [int]$Catalog.routes.ui_button_release.slf_indices[0]
    })[0]
    $globalAlarmEntry = @($environment | Where-Object {
        [int]$_.zero_based_index -eq [int]$Catalog.routes.global_alarm.slf_indices[0]
    })[0]
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('#pragma once')
    $lines.Add('')
    $lines.Add('// Generated from SDK/sound-routes.json. Do not edit.')
    $lines.Add('#include <array>')
    $lines.Add('#include <cstddef>')
    $lines.Add('')
    $lines.Add('namespace m1937::sdk::sound {')
    $lines.Add('')
    $lines.Add(('inline constexpr int slf_entry_count = {0};' -f [int]$Catalog.slf_entry_count))
    $lines.Add(('inline constexpr int sprite_group_parameter_index = {0};' -f [int]$Catalog.routes.sprite_group.parameter_index))
    $lines.Add(('inline constexpr int audited_sprite_count = {0};' -f [int]$Catalog.routes.sprite_group.audited_sprite_count))
    $lines.Add(('inline constexpr int audited_group_count = {0};' -f [int]$Catalog.routes.sprite_group.audited_group_count))
    $lines.Add(('inline constexpr int sounded_group_count = {0};' -f [int]$Catalog.routes.sprite_group.sounded_group_count))
    $lines.Add(('inline constexpr int ui_button_zero_based_index = {0};' -f [int]$Catalog.routes.ui_button_release.slf_indices[0]))
    $lines.Add(('inline constexpr int ui_button_gfl_index = {0};' -f [int]$uiButtonEntry.gfl_index))
    $lines.Add(('inline constexpr int global_alarm_zero_based_index = {0};' -f [int]$Catalog.routes.global_alarm.slf_indices[0]))
    $lines.Add(('inline constexpr int global_alarm_gfl_index = {0};' -f [int]$globalAlarmEntry.gfl_index))
    $lines.Add(('inline constexpr int global_alarm_update_counter_limit = {0};' -f [int]$Catalog.routes.global_alarm.update_counter_limit))
    $lines.Add(('inline constexpr int global_alarm_active_request_updates = {0};' -f [int]$Catalog.routes.global_alarm.active_request_updates))
    $lines.Add('')
    $lines.Add(('inline constexpr std::array<int, {0}> sprite_group_one_based_indices{{{{' -f $sprite.Count))
    $lines.Add(('    {0}' -f (Format-IntegerArray $sprite)))
    $lines.Add('}};')
    $lines.Add(('inline constexpr std::array<int, {0}> actor_voice_zero_based_indices{{{{' -f $voice.Count))
    $lines.Add(('    {0}' -f (Format-IntegerArray $voice)))
    $lines.Add('}};')
    $lines.Add(('inline constexpr std::array<int, {0}> reachable_zero_based_indices{{{{' -f $reachable.Count))
    $lines.Add(('    {0}' -f (Format-IntegerArray $reachable)))
    $lines.Add('}};')
    $lines.Add(('inline constexpr std::array<int, {0}> asset_only_zero_based_indices{{{{' -f $assetOnly.Count))
    $lines.Add(('    {0}' -f (Format-IntegerArray $assetOnly)))
    $lines.Add('}};')
    $lines.Add('')
    $lines.Add('template <std::size_t Size>')
    $lines.Add('constexpr bool contains(')
    $lines.Add('    const std::array<int, Size>& values, int value) noexcept {')
    $lines.Add('    for (const auto candidate : values)')
    $lines.Add('        if (candidate == value)')
    $lines.Add('            return true;')
    $lines.Add('    return false;')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add('constexpr bool is_reachable_zero_based(int index) noexcept {')
    $lines.Add('    return contains(reachable_zero_based_indices, index);')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add('constexpr bool is_asset_only_zero_based(int index) noexcept {')
    $lines.Add('    return contains(asset_only_zero_based_indices, index);')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add('struct AuditedEnvironmentEntry final {')
    $lines.Add('    int zero_based_index;')
    $lines.Add('    int one_based_index;')
    $lines.Add('    int gfl_index;')
    $lines.Add('    const char* category;')
    $lines.Add('    const char* event_key;')
    $lines.Add('    const char* resource_name;')
    $lines.Add('    const char* reachability;')
    $lines.Add('};')
    $lines.Add('')
    $lines.Add(('inline constexpr std::array<AuditedEnvironmentEntry, {0}> audited_environment_entries{{{{' -f $environment.Count))
    foreach ($entry in $environment) {
        $lines.Add(('    {{{0}, {1}, {2}, "{3}", "{4}", "{5}", "{6}"}},' -f
            [int]$entry.zero_based_index,
            [int]$entry.one_based_index,
            [int]$entry.gfl_index,
            (Escape-CppString ([string]$entry.category)),
            (Escape-CppString ([string]$entry.event_key)),
            (Escape-CppString ([string]$entry.resource_name)),
            (Escape-CppString ([string]$entry.reachability))))
    }
    $lines.Add('}};')
    $lines.Add('')
    $lines.Add('constexpr const AuditedEnvironmentEntry* find_environment_entry(')
    $lines.Add('    int zero_based_index) noexcept {')
    $lines.Add('    for (const auto& entry : audited_environment_entries)')
    $lines.Add('        if (entry.zero_based_index == zero_based_index)')
    $lines.Add('            return &entry;')
    $lines.Add('    return nullptr;')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add('}  // namespace m1937::sdk::sound')
    $lines.Add('')
    return [string]::Join("`n", $lines)
}

function New-GdscriptSoundCatalog {
    param($Catalog)
    $sprite = @($Catalog.routes.sprite_group.unique_slf_indices)
    $voice = @($Catalog.routes.actor_voice.unique_slf_indices)
    $reachable = @($Catalog.reachable_zero_based_indices)
    $assetOnly = @($Catalog.asset_only_zero_based_indices)
    $environment = @($Catalog.audited_environment_and_ui_entries)
    $uiButtonEntry = @($environment | Where-Object {
        [int]$_.zero_based_index -eq [int]$Catalog.routes.ui_button_release.slf_indices[0]
    })[0]
    $globalAlarmEntry = @($environment | Where-Object {
        [int]$_.zero_based_index -eq [int]$Catalog.routes.global_alarm.slf_indices[0]
    })[0]
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('class_name LegacySoundRouteCatalog')
    $lines.Add('extends RefCounted')
    $lines.Add('')
    $lines.Add('## Generated from SDK/sound-routes.json. Do not edit.')
    $lines.Add(('const SLF_ENTRY_COUNT := {0}' -f [int]$Catalog.slf_entry_count))
    $lines.Add(('const SPRITE_GROUP_PARAMETER_INDEX := {0}' -f [int]$Catalog.routes.sprite_group.parameter_index))
    $lines.Add(('const AUDITED_SPRITE_COUNT := {0}' -f [int]$Catalog.routes.sprite_group.audited_sprite_count))
    $lines.Add(('const AUDITED_GROUP_COUNT := {0}' -f [int]$Catalog.routes.sprite_group.audited_group_count))
    $lines.Add(('const SOUNDED_GROUP_COUNT := {0}' -f [int]$Catalog.routes.sprite_group.sounded_group_count))
    $lines.Add(('const UI_BUTTON_ZERO_BASED_INDEX := {0}' -f [int]$Catalog.routes.ui_button_release.slf_indices[0]))
    $lines.Add(('const UI_BUTTON_GFL_INDEX := {0}' -f [int]$uiButtonEntry.gfl_index))
    $lines.Add(('const GLOBAL_ALARM_ZERO_BASED_INDEX := {0}' -f [int]$Catalog.routes.global_alarm.slf_indices[0]))
    $lines.Add(('const GLOBAL_ALARM_GFL_INDEX := {0}' -f [int]$globalAlarmEntry.gfl_index))
    $lines.Add(('const GLOBAL_ALARM_UPDATE_COUNTER_LIMIT := {0}' -f [int]$Catalog.routes.global_alarm.update_counter_limit))
    $lines.Add(('const GLOBAL_ALARM_ACTIVE_REQUEST_UPDATES := {0}' -f [int]$Catalog.routes.global_alarm.active_request_updates))
    $lines.Add(('const SPRITE_GROUP_ONE_BASED_INDICES: Array[int] = [{0}]' -f (Format-IntegerArray $sprite)))
    $lines.Add(('const ACTOR_VOICE_ZERO_BASED_INDICES: Array[int] = [{0}]' -f (Format-IntegerArray $voice)))
    $lines.Add(('const REACHABLE_ZERO_BASED_INDICES: Array[int] = [{0}]' -f (Format-IntegerArray $reachable)))
    $lines.Add(('const ASSET_ONLY_ZERO_BASED_INDICES: Array[int] = [{0}]' -f (Format-IntegerArray $assetOnly)))
    $lines.Add('const AUDITED_ENVIRONMENT_ENTRIES: Array[Dictionary] = [')
    foreach ($entry in $environment) {
        $lines.Add(('    {{"zero_based_index": {0}, "one_based_index": {1}, "gfl_index": {2}, "category": "{3}", "event_key": "{4}", "resource_name": "{5}", "reachability": "{6}"}},' -f
            [int]$entry.zero_based_index,
            [int]$entry.one_based_index,
            [int]$entry.gfl_index,
            (Escape-GdString ([string]$entry.category)),
            (Escape-GdString ([string]$entry.event_key)),
            (Escape-GdString ([string]$entry.resource_name)),
            (Escape-GdString ([string]$entry.reachability))))
    }
    $lines.Add(']')
    $lines.Add('')
    $lines.Add('static func is_reachable_zero_based(index: int) -> bool:')
    $lines.Add('    return REACHABLE_ZERO_BASED_INDICES.has(index)')
    $lines.Add('')
    $lines.Add('static func is_asset_only_zero_based(index: int) -> bool:')
    $lines.Add('    return ASSET_ONLY_ZERO_BASED_INDICES.has(index)')
    $lines.Add('')
    $lines.Add('static func environment_entry(index: int) -> Dictionary:')
    $lines.Add('    for entry: Dictionary in AUDITED_ENVIRONMENT_ENTRIES:')
    $lines.Add('        if int(entry.get("zero_based_index", -1)) == index:')
    $lines.Add('            return entry.duplicate(true)')
    $lines.Add('    return {}')
    $lines.Add('')
    return [string]::Join("`n", $lines)
}

function New-MediaHeader {
    param($Catalog)
    $startup = @($Catalog.startup_sequence)
    $briefings = @($Catalog.level_briefings)
    $endings = @($Catalog.ending_images)
    $direction = $Catalog.original_direction_flow
    $cameraCallers = @($direction.camera.direct_callers)
    $cameraWriters = @($direction.camera.writer_symbols)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('#pragma once')
    $lines.Add('')
    $lines.Add('// Generated from SDK/media-routes.json. Do not edit.')
    $lines.Add('#include <array>')
    $lines.Add('#include <cstdint>')
    $lines.Add('')
    $lines.Add('namespace m1937::sdk::media {')
    $lines.Add('')
    $lines.Add(('inline constexpr bool movie_player_blocks = {0};' -f $(
        if ([bool]$Catalog.movie_player.blocking_until_finished_or_input) {
            'true'
        } else {
            'false'
        })))
    $lines.Add(('inline constexpr int executable_svt_string_count = {0};' -f
        [int]$Catalog.movie_player.executable_svt_string_count))
    $lines.Add(('inline constexpr int direct_movie_call_count = {0};' -f
        [int]$Catalog.movie_player.direct_call_count))
    $lines.Add(('inline constexpr int inter_level_movie_count = {0};' -f
        [int]$Catalog.presentation_flow.inter_level_movie_count))
    $lines.Add(('inline constexpr int ending_selector_level = {0};' -f
        [int]$Catalog.presentation_flow.ending_selector_level))
    $lines.Add(('inline constexpr int ending_dismissal_next_selector_level = {0};' -f
        [int]$Catalog.presentation_flow.ending_dismissal_next_selector_level))
    $lines.Add(('inline constexpr int presentation_string_count = {0};' -f
        [int]$direction.presentation_string_count))
    $lines.Add(('inline constexpr int in_mission_dialogue_sequence_count = {0};' -f
        [int]$direction.in_mission_dialogue_sequence_count))
    $lines.Add(('inline constexpr int scripted_camera_sequence_count = {0};' -f
        [int]$direction.scripted_camera_sequence_count))
    $lines.Add(('inline constexpr int per_level_tutorial_sequence_count = {0};' -f
        [int]$direction.per_level_tutorial_sequence_count))
    $lines.Add(('inline constexpr bool mission_flow_reaches_movie_or_camera = {0};' -f $(
        if ([bool]$direction.mission_flow_reaches_movie_or_camera) {
            'true'
        } else {
            'false'
        })))
    $lines.Add(('inline constexpr int camera_direct_call_count = {0};' -f
        [int]$direction.camera.direct_call_count))
    $lines.Add(('inline constexpr int mission_script_camera_writer_count = {0};' -f
        [int]$direction.camera.mission_script_writer_count))
    $lines.Add(('inline constexpr const char* original_profile_policy = "{0}";' -f
        (Escape-CppString ([string]$direction.original_profile_policy))))
    $lines.Add('')
    $lines.Add('struct GlobalHelpRoute final {')
    $lines.Add('    const char* resource_name;')
    $lines.Add('    std::uintptr_t resource_string_rva;')
    $lines.Add('    const char* presenter_symbol;')
    $lines.Add('    const char* scope;')
    $lines.Add('};')
    $lines.Add('')
    $lines.Add(('inline constexpr GlobalHelpRoute global_help{{"{0}", {1}, "{2}", "{3}"}};' -f
        (Escape-CppString ([string]$direction.global_help.resource_name)),
        (Format-Rva ([string]$direction.global_help.resource_string_rva)),
        (Escape-CppString ([string]$direction.global_help.presenter_symbol)),
        (Escape-CppString ([string]$direction.global_help.scope))))
    $lines.Add('')
    $lines.Add('struct CameraDirectCall final {')
    $lines.Add('    const char* caller_symbol;')
    $lines.Add('    const char* call_site_symbol;')
    $lines.Add('    std::uintptr_t call_rva;')
    $lines.Add('    const char* role;')
    $lines.Add('};')
    $lines.Add('')
    $lines.Add(('inline constexpr std::array<CameraDirectCall, {0}> camera_direct_callers{{{{' -f
        $cameraCallers.Count))
    foreach ($entry in $cameraCallers) {
        $lines.Add(('    {{"{0}", "{1}", {2}, "{3}"}},' -f
            (Escape-CppString ([string]$entry.caller_symbol)),
            (Escape-CppString ([string]$entry.call_site_symbol)),
            (Format-Rva ([string]$entry.call_rva)),
            (Escape-CppString ([string]$entry.role))))
    }
    $lines.Add('}};')
    $lines.Add('')
    $lines.Add(('inline constexpr std::array<const char*, {0}> camera_writer_symbols{{{{' -f
        $cameraWriters.Count))
    foreach ($symbol in $cameraWriters) {
        $lines.Add(('    "{0}",' -f (Escape-CppString ([string]$symbol))))
    }
    $lines.Add('}};')
    $lines.Add('')
    $lines.Add('struct StartupMovie final {')
    $lines.Add('    int order;')
    $lines.Add('    const char* id;')
    $lines.Add('    const char* role;')
    $lines.Add('    const char* source_filename;')
    $lines.Add('    const char* source_disk_filename;')
    $lines.Add('    std::uintptr_t source_string_rva;')
    $lines.Add('    std::uintptr_t call_rva;')
    $lines.Add('    int player_argument_1;')
    $lines.Add('    int player_argument_2;')
    $lines.Add('    int source_width;')
    $lines.Add('    int source_height;')
    $lines.Add('    double duration_seconds;')
    $lines.Add('    const char* converted_relative_path;')
    $lines.Add('};')
    $lines.Add('')
    $lines.Add(('inline constexpr std::array<StartupMovie, {0}> startup_sequence{{{{' -f
        $startup.Count))
    foreach ($entry in $startup) {
        $lines.Add(('    {{{0}, "{1}", "{2}", "{3}", "{4}", {5}, {6}, {7}, {8}, {9}, {10}, {11}, "{12}"}},' -f
            [int]$entry.order,
            (Escape-CppString ([string]$entry.id)),
            (Escape-CppString ([string]$entry.role)),
            (Escape-CppString ([string]$entry.source_filename)),
            (Escape-CppString ([string]$entry.source_disk_filename)),
            (Format-Rva ([string]$entry.source_string_rva)),
            (Format-Rva ([string]$entry.call_rva)),
            [int]$entry.player_argument_1,
            [int]$entry.player_argument_2,
            [int]$entry.source_width,
            [int]$entry.source_height,
            ([double]$entry.duration_seconds).ToString(
                '0.000000', [Globalization.CultureInfo]::InvariantCulture),
            (Escape-CppString ([string]$entry.converted_relative_path))))
    }
    $lines.Add('}};')
    $lines.Add('')
    $lines.Add('struct LevelBriefing final {')
    $lines.Add('    int selector_level;')
    $lines.Add('    const char* level_id;')
    $lines.Add('    const char* resource_name;')
    $lines.Add('    int gfl_index;')
    $lines.Add('    const char* converted_relative_path;')
    $lines.Add('};')
    $lines.Add('')
    $lines.Add(('inline constexpr std::array<LevelBriefing, {0}> level_briefings{{{{' -f
        $briefings.Count))
    foreach ($entry in $briefings) {
        $lines.Add(('    {{{0}, "{1}", "{2}", {3}, "{4}"}},' -f
            [int]$entry.selector_level,
            (Escape-CppString ([string]$entry.level_id)),
            (Escape-CppString ([string]$entry.resource_name)),
            [int]$entry.gfl_index,
            (Escape-CppString ([string]$entry.converted_relative_path))))
    }
    $lines.Add('}};')
    $lines.Add('')
    $lines.Add('struct EndingImage final {')
    $lines.Add('    int target_width;')
    $lines.Add('    const char* resource_name;')
    $lines.Add('    std::uintptr_t resource_string_rva;')
    $lines.Add('    int gfl_index;')
    $lines.Add('    const char* converted_relative_path;')
    $lines.Add('};')
    $lines.Add('')
    $lines.Add(('inline constexpr std::array<EndingImage, {0}> ending_images{{{{' -f
        $endings.Count))
    foreach ($entry in $endings) {
        $lines.Add(('    {{{0}, "{1}", {2}, {3}, "{4}"}},' -f
            [int]$entry.target_width,
            (Escape-CppString ([string]$entry.resource_name)),
            (Format-Rva ([string]$entry.resource_string_rva)),
            [int]$entry.gfl_index,
            (Escape-CppString ([string]$entry.converted_relative_path))))
    }
    $lines.Add('}};')
    $lines.Add('')
    $lines.Add('}  // namespace m1937::sdk::media')
    $lines.Add('')
    return [string]::Join("`n", $lines)
}

function New-GdscriptMediaCatalog {
    param($Catalog)
    $direction = $Catalog.original_direction_flow
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('class_name LegacyMediaRouteCatalog')
    $lines.Add('extends RefCounted')
    $lines.Add('')
    $lines.Add('## Generated from SDK/media-routes.json. Do not edit.')
    $lines.Add(('const CATALOG_ID := "{0}"' -f
        (Escape-GdString ([string]$Catalog.catalog_id))))
    $lines.Add(('const MOVIE_PLAYER_BLOCKS := {0}' -f $(
        if ([bool]$Catalog.movie_player.blocking_until_finished_or_input) {
            'true'
        } else {
            'false'
        })))
    $lines.Add(('const EXECUTABLE_SVT_STRING_COUNT := {0}' -f
        [int]$Catalog.movie_player.executable_svt_string_count))
    $lines.Add(('const DIRECT_MOVIE_CALL_COUNT := {0}' -f
        [int]$Catalog.movie_player.direct_call_count))
    $lines.Add(('const INTER_LEVEL_MOVIE_COUNT := {0}' -f
        [int]$Catalog.presentation_flow.inter_level_movie_count))
    $lines.Add(('const ENDING_SELECTOR_LEVEL := {0}' -f
        [int]$Catalog.presentation_flow.ending_selector_level))
    $lines.Add(('const ENDING_DISMISSAL_NEXT_SELECTOR_LEVEL := {0}' -f
        [int]$Catalog.presentation_flow.ending_dismissal_next_selector_level))
    $lines.Add(('const PRESENTATION_STRING_COUNT := {0}' -f
        [int]$direction.presentation_string_count))
    $lines.Add(('const IN_MISSION_DIALOGUE_SEQUENCE_COUNT := {0}' -f
        [int]$direction.in_mission_dialogue_sequence_count))
    $lines.Add(('const SCRIPTED_CAMERA_SEQUENCE_COUNT := {0}' -f
        [int]$direction.scripted_camera_sequence_count))
    $lines.Add(('const PER_LEVEL_TUTORIAL_SEQUENCE_COUNT := {0}' -f
        [int]$direction.per_level_tutorial_sequence_count))
    $lines.Add(('const MISSION_FLOW_REACHES_MOVIE_OR_CAMERA := {0}' -f $(
        if ([bool]$direction.mission_flow_reaches_movie_or_camera) {
            'true'
        } else {
            'false'
        })))
    $lines.Add(('const CAMERA_DIRECT_CALL_COUNT := {0}' -f
        [int]$direction.camera.direct_call_count))
    $lines.Add(('const MISSION_SCRIPT_CAMERA_WRITER_COUNT := {0}' -f
        [int]$direction.camera.mission_script_writer_count))
    $lines.Add(('const ORIGINAL_PROFILE_POLICY := "{0}"' -f
        (Escape-GdString ([string]$direction.original_profile_policy))))
    $lines.Add(('const GLOBAL_HELP: Dictionary = {{"resource_name": "{0}", "resource_string_rva": {1}, "presenter_symbol": "{2}", "scope": "{3}"}}' -f
        (Escape-GdString ([string]$direction.global_help.resource_name)),
        (Format-Rva ([string]$direction.global_help.resource_string_rva)),
        (Escape-GdString ([string]$direction.global_help.presenter_symbol)),
        (Escape-GdString ([string]$direction.global_help.scope))))
    $lines.Add('const CAMERA_DIRECT_CALLERS: Array[Dictionary] = [')
    foreach ($entry in $direction.camera.direct_callers) {
        $lines.Add(('    {{"caller_symbol": "{0}", "call_site_symbol": "{1}", "call_rva": {2}, "role": "{3}"}},' -f
            (Escape-GdString ([string]$entry.caller_symbol)),
            (Escape-GdString ([string]$entry.call_site_symbol)),
            (Format-Rva ([string]$entry.call_rva)),
            (Escape-GdString ([string]$entry.role))))
    }
    $lines.Add(']')
    $lines.Add('const CAMERA_WRITER_SYMBOLS: Array[String] = [')
    foreach ($symbol in $direction.camera.writer_symbols) {
        $lines.Add(('    "{0}",' -f (Escape-GdString ([string]$symbol))))
    }
    $lines.Add(']')
    $lines.Add('const STARTUP_SEQUENCE: Array[Dictionary] = [')
    foreach ($entry in $Catalog.startup_sequence) {
        $lines.Add(('    {{"order": {0}, "id": "{1}", "role": "{2}", "source_filename": "{3}", "source_disk_filename": "{4}", "source_string_rva": {5}, "call_rva": {6}, "player_argument_1": {7}, "player_argument_2": {8}, "source_width": {9}, "source_height": {10}, "duration_seconds": {11}, "converted_relative_path": "{12}"}},' -f
            [int]$entry.order,
            (Escape-GdString ([string]$entry.id)),
            (Escape-GdString ([string]$entry.role)),
            (Escape-GdString ([string]$entry.source_filename)),
            (Escape-GdString ([string]$entry.source_disk_filename)),
            (Format-Rva ([string]$entry.source_string_rva)),
            (Format-Rva ([string]$entry.call_rva)),
            [int]$entry.player_argument_1,
            [int]$entry.player_argument_2,
            [int]$entry.source_width,
            [int]$entry.source_height,
            ([double]$entry.duration_seconds).ToString(
                '0.000000', [Globalization.CultureInfo]::InvariantCulture),
            (Escape-GdString ([string]$entry.converted_relative_path))))
    }
    $lines.Add(']')
    $lines.Add('const LEVEL_BRIEFINGS: Array[Dictionary] = [')
    foreach ($entry in $Catalog.level_briefings) {
        $lines.Add(('    {{"selector_level": {0}, "level_id": "{1}", "resource_name": "{2}", "gfl_index": {3}, "converted_relative_path": "{4}"}},' -f
            [int]$entry.selector_level,
            (Escape-GdString ([string]$entry.level_id)),
            (Escape-GdString ([string]$entry.resource_name)),
            [int]$entry.gfl_index,
            (Escape-GdString ([string]$entry.converted_relative_path))))
    }
    $lines.Add(']')
    $lines.Add('const ENDING_IMAGES: Array[Dictionary] = [')
    foreach ($entry in $Catalog.ending_images) {
        $lines.Add(('    {{"target_width": {0}, "resource_name": "{1}", "resource_string_rva": {2}, "gfl_index": {3}, "converted_relative_path": "{4}"}},' -f
            [int]$entry.target_width,
            (Escape-GdString ([string]$entry.resource_name)),
            (Format-Rva ([string]$entry.resource_string_rva)),
            [int]$entry.gfl_index,
            (Escape-GdString ([string]$entry.converted_relative_path))))
    }
    $lines.Add(']')
    $lines.Add('')
    $lines.Add('static func startup_sequence() -> Array[Dictionary]:')
    $lines.Add('    return STARTUP_SEQUENCE.duplicate(true)')
    $lines.Add('')
    $lines.Add('static func briefing_for_level(level_id: String) -> Dictionary:')
    $lines.Add('    for entry: Dictionary in LEVEL_BRIEFINGS:')
    $lines.Add('        if str(entry.get("level_id", "")) == level_id:')
    $lines.Add('            return entry.duplicate(true)')
    $lines.Add('    return {}')
    $lines.Add('')
    $lines.Add('static func ending_for_target_width(target_width: int) -> Dictionary:')
    $lines.Add('    var best: Dictionary = {}')
    $lines.Add('    var best_distance := 0x7fffffff')
    $lines.Add('    for entry: Dictionary in ENDING_IMAGES:')
    $lines.Add('        var distance := absi(int(entry.get("target_width", 0)) - target_width)')
    $lines.Add('        if distance < best_distance:')
    $lines.Add('            best_distance = distance')
    $lines.Add('            best = entry')
    $lines.Add('    return best.duplicate(true)')
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
$soundCatalog =
    Get-Content -LiteralPath $soundPath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$mediaCatalog =
    Get-Content -LiteralPath $mediaPath -Raw -Encoding UTF8 |
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
if ([string]$soundCatalog.supported_executable_sha256 -cne
    [string]$addressCatalog.supported_executable.sha256) {
    throw 'Sound route catalog targets a different executable identity.'
}
if ([string]$mediaCatalog.supported_executable_sha256 -cne
    [string]$addressCatalog.supported_executable.sha256) {
    throw 'Media route catalog targets a different executable identity.'
}
$addressNames = @($addressCatalog.addresses.name)
$mediaSymbols = @(
    [string]$mediaCatalog.movie_player.thunk_symbol
    [string]$mediaCatalog.movie_player.function_symbol
    [string]$mediaCatalog.movie_player.frame_update_symbol
    [string]$mediaCatalog.movie_player.startup_sequence_symbol
    [string]$mediaCatalog.presentation_flow.asset_selector_symbol
    [string]$mediaCatalog.presentation_flow.display_and_level_load_symbol
    [string]$mediaCatalog.original_direction_flow.global_help.presenter_symbol
    [string]$mediaCatalog.original_direction_flow.camera.setter_symbol
    @($mediaCatalog.original_direction_flow.camera.direct_callers |
        ForEach-Object {
            [string]$_.caller_symbol
            [string]$_.call_site_symbol
        })
    @($mediaCatalog.original_direction_flow.camera.writer_symbols |
        ForEach-Object { [string]$_ })
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique
$missingMediaSymbols = @($mediaSymbols |
    Where-Object { $addressNames -notcontains $_ })
if ($missingMediaSymbols.Count -ne 0) {
    throw (
        'Media route catalog references missing address symbols: ' +
        ($missingMediaSymbols -join ', '))
}
$startupMovies = @($mediaCatalog.startup_sequence)
if ($startupMovies.Count -ne 2 -or
    [int]$mediaCatalog.movie_player.executable_svt_string_count -ne 2 -or
    [int]$mediaCatalog.movie_player.direct_call_count -ne 2 -or
    -not [bool]$mediaCatalog.movie_player.blocking_until_finished_or_input) {
    throw 'Original movie route must contain exactly two blocking startup calls.'
}
$expectedStartupMovies = @(
    [pscustomobject]@{
        order = 0
        id = 'logo'
        source_filename = 'GameKingLogo.SVT'
        call_rva = '0x00007635'
        argument_2 = 0
    },
    [pscustomobject]@{
        order = 1
        id = 'historical_intro'
        source_filename = '1937Intro.SVT'
        call_rva = '0x00007644'
        argument_2 = 100
    }
)
for ($startupIndex = 0; $startupIndex -lt 2; $startupIndex++) {
    $entry = $startupMovies[$startupIndex]
    $expected = $expectedStartupMovies[$startupIndex]
    if ([int]$entry.order -ne [int]$expected.order -or
        [string]$entry.id -cne [string]$expected.id -or
        [string]$entry.source_filename -cne [string]$expected.source_filename -or
        (Format-Rva ([string]$entry.call_rva)) -cne
            (Format-Rva ([string]$expected.call_rva)) -or
        [int]$entry.player_argument_1 -ne 0 -or
        [int]$entry.player_argument_2 -ne [int]$expected.argument_2 -or
        [string]::IsNullOrWhiteSpace(
            [string]$entry.converted_relative_path)) {
        throw "Invalid original startup movie entry at order $startupIndex."
    }
}
$mediaBriefings = @($mediaCatalog.level_briefings)
if ($mediaBriefings.Count -ne 12) {
    throw 'Media route catalog must contain the twelve original briefings.'
}
for ($briefingIndex = 0; $briefingIndex -lt 12; $briefingIndex++) {
    $entry = $mediaBriefings[$briefingIndex]
    $expectedSelector = $briefingIndex + 1
    $expectedLevelId = 'm{0:D3}' -f $briefingIndex
    $expectedResourceName = 'Intro_{0:D3}.psd' -f $briefingIndex
    if ([int]$entry.selector_level -ne $expectedSelector -or
        [string]$entry.level_id -cne $expectedLevelId -or
        [string]$entry.resource_name -cne $expectedResourceName) {
        throw "Invalid original briefing entry at selector $expectedSelector."
    }
}
$endingWidths = @($mediaCatalog.ending_images |
    ForEach-Object { [int]$_.target_width } | Sort-Object)
if ([int]$mediaCatalog.presentation_flow.inter_level_movie_count -ne 0 -or
    [int]$mediaCatalog.presentation_flow.ending_selector_level -ne 13 -or
    [int]$mediaCatalog.presentation_flow.ending_dismissal_next_selector_level -ne 1 -or
    (Compare-Object @(640, 800, 1024) $endingWidths).Count -ne 0) {
    throw 'Original briefing/ending presentation flow is inconsistent.'
}
$direction = $mediaCatalog.original_direction_flow
$cameraCallers = @($direction.camera.direct_callers)
$cameraWriters = @($direction.camera.writer_symbols)
$expectedCameraCallers = @(
    [pscustomobject]@{
        caller_symbol = 'WorldInputDispatch'
        call_site_symbol = 'WorldInputCameraSetCall'
        call_rva = '0x0004CC23'
        role = 'world_input_recenter'
    },
    [pscustomobject]@{
        caller_symbol = 'FocusActorCamera'
        call_site_symbol = 'FocusActorCameraSetCall'
        call_rva = '0x0004CD8B'
        role = 'explicit_actor_focus'
    }
)
$expectedCameraWriters = @(
    'InitializeViewport',
    'SetCameraOrigin',
    'ScrollLeft',
    'ScrollRight',
    'ScrollUp',
    'ScrollDown',
    'ResizeViewportWorld',
    'LoadGameFile'
)
if ([int]$direction.presentation_string_count -ne 27 -or
    [int]$direction.in_mission_dialogue_sequence_count -ne 0 -or
    [int]$direction.scripted_camera_sequence_count -ne 0 -or
    [int]$direction.per_level_tutorial_sequence_count -ne 0 -or
    [bool]$direction.mission_flow_reaches_movie_or_camera -or
    [int]$direction.camera.direct_call_count -ne 2 -or
    [int]$direction.camera.mission_script_writer_count -ne 0 -or
    $cameraCallers.Count -ne 2 -or
    $cameraWriters.Count -ne $expectedCameraWriters.Count -or
    [string]$direction.global_help.resource_name -cne 'Help.psd' -or
    (Format-Rva ([string]$direction.global_help.resource_string_rva)) -cne
        '0x000CF704' -or
    [string]$direction.global_help.presenter_symbol -cne 'HelpPresenter' -or
    [string]$direction.global_help.scope -cne 'global_f1_help' -or
    [string]::IsNullOrWhiteSpace([string]$direction.original_profile_policy)) {
    throw 'Original dialogue/camera/tutorial closure is inconsistent.'
}
for ($callerIndex = 0; $callerIndex -lt $expectedCameraCallers.Count; $callerIndex++) {
    $entry = $cameraCallers[$callerIndex]
    $expected = $expectedCameraCallers[$callerIndex]
    if ([string]$entry.caller_symbol -cne [string]$expected.caller_symbol -or
        [string]$entry.call_site_symbol -cne [string]$expected.call_site_symbol -or
        (Format-Rva ([string]$entry.call_rva)) -cne
            (Format-Rva ([string]$expected.call_rva)) -or
        [string]$entry.role -cne [string]$expected.role) {
        throw "Invalid original camera caller at index $callerIndex."
    }
}
for ($writerIndex = 0; $writerIndex -lt $expectedCameraWriters.Count; $writerIndex++) {
    if ([string]$cameraWriters[$writerIndex] -cne
        [string]$expectedCameraWriters[$writerIndex]) {
        throw "Invalid original camera writer at index $writerIndex."
    }
}
$soundSymbols = @(
    [string]$soundCatalog.request_pipeline.queued.manager_request_symbol
    [string]$soundCatalog.request_pipeline.queued.request_counter_symbol
    [string]$soundCatalog.request_pipeline.queued.frame_update_symbol
    [string]$soundCatalog.request_pipeline.queued.buffer_start_symbol
    @($soundCatalog.request_pipeline.queued.direct_callers |
        ForEach-Object { [string]$_ })
    [string]$soundCatalog.request_pipeline.immediate.manager_request_symbol
    [string]$soundCatalog.request_pipeline.immediate.buffer_start_symbol
    @($soundCatalog.request_pipeline.immediate.direct_callers |
        ForEach-Object { [string]$_ })
    [string]$soundCatalog.routes.sprite_group.dispatcher_symbol
    [string]$soundCatalog.routes.sprite_group.request_symbol
    [string]$soundCatalog.routes.actor_voice.request_symbol
    @($soundCatalog.routes.actor_voice.selector_symbols |
        ForEach-Object { [string]$_ })
    [string]$soundCatalog.routes.global_alarm.request_symbol
    [string]$soundCatalog.routes.global_alarm.caller_symbol
    [string]$soundCatalog.routes.global_alarm.call_sequence_symbol
    [string]$soundCatalog.routes.ui_button_release.request_symbol
    [string]$soundCatalog.routes.ui_button_release.caller_symbol
    [string]$soundCatalog.routes.ui_button_release.call_sequence_symbol
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique
$missingSoundSymbols = @($soundSymbols |
    Where-Object { $addressNames -notcontains $_ })
if ($missingSoundSymbols.Count -ne 0) {
    throw (
        'Sound route catalog references missing address symbols: ' +
        ($missingSoundSymbols -join ', '))
}
$spriteSoundIndices = @(
    $soundCatalog.routes.sprite_group.unique_slf_indices |
        ForEach-Object { [int]$_ })
$voiceSoundIndices = @(
    $soundCatalog.routes.actor_voice.unique_slf_indices |
        ForEach-Object { [int]$_ })
$directSoundIndices = @(
    $soundCatalog.routes.global_alarm.slf_indices |
        ForEach-Object { [int]$_ }) + @(
    $soundCatalog.routes.ui_button_release.slf_indices |
        ForEach-Object { [int]$_ })
$derivedReachable = @(
    @($spriteSoundIndices | ForEach-Object { $_ - 1 }) +
    $voiceSoundIndices +
    $directSoundIndices |
        Sort-Object -Unique)
$declaredReachable = @(
    $soundCatalog.reachable_zero_based_indices |
        ForEach-Object { [int]$_ })
$assetOnlySoundIndices = @(
    $soundCatalog.asset_only_zero_based_indices |
        ForEach-Object { [int]$_ })
$allSoundIndices = @(0..([int]$soundCatalog.slf_entry_count - 1))
if ((Compare-Object $derivedReachable $declaredReachable).Count -ne 0 -or
    $declaredReachable.Count -ne
        ($declaredReachable | Sort-Object -Unique).Count -or
    $assetOnlySoundIndices.Count -ne
        ($assetOnlySoundIndices | Sort-Object -Unique).Count -or
    (Compare-Object $allSoundIndices @(
        $declaredReachable + $assetOnlySoundIndices |
            Sort-Object -Unique)).Count -ne 0 -or
    @($declaredReachable |
        Where-Object { $assetOnlySoundIndices -contains $_ }).Count -ne 0) {
    throw (
        'Sound route reachability must be the exact disjoint partition of ' +
        'the SLF library derived from its four executable routes.')
}
foreach ($entry in $soundCatalog.audited_environment_and_ui_entries) {
    $zeroBased = [int]$entry.zero_based_index
    if ([int]$entry.one_based_index -ne $zeroBased + 1 -or
        $zeroBased -lt 0 -or
        $zeroBased -ge [int]$soundCatalog.slf_entry_count -or
        [string]::IsNullOrWhiteSpace([string]$entry.resource_name) -or
        ([string]$entry.reachability -eq 'asset_only') -ne
            ($assetOnlySoundIndices -contains $zeroBased)) {
        throw "Invalid audited sound entry at zero-based index $zeroBased."
    }
}
$uiButtonEntries = @($soundCatalog.audited_environment_and_ui_entries |
    Where-Object {
        [int]$_.zero_based_index -eq
            [int]$soundCatalog.routes.ui_button_release.slf_indices[0]
    })
$globalAlarmEntries = @($soundCatalog.audited_environment_and_ui_entries |
    Where-Object {
        [int]$_.zero_based_index -eq
            [int]$soundCatalog.routes.global_alarm.slf_indices[0]
    })
if ($uiButtonEntries.Count -ne 1 -or
    [string]$uiButtonEntries[0].reachability -ne 'ui_button_immediate' -or
    $globalAlarmEntries.Count -ne 1 -or
    [string]$globalAlarmEntries[0].reachability -ne
        'sprite_group_and_general_queued' -or
    [int]$soundCatalog.routes.global_alarm.update_counter_limit -ne 240 -or
    [int]$soundCatalog.routes.global_alarm.active_request_updates -ne 241) {
    throw 'Sound route special UI/alarm identities or timing are invalid.'
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
    (Join-Path $sdkRoot 'include\M1937SDK\Sound.hpp') =
        New-SoundHeader $soundCatalog
    (Join-Path $repositoryRoot (
        'Remake\game\scripts\generated\legacy_sound_route_catalog.gd')) =
        New-GdscriptSoundCatalog $soundCatalog
    (Join-Path $sdkRoot 'include\M1937SDK\Media.hpp') =
        New-MediaHeader $mediaCatalog
    (Join-Path $repositoryRoot (
        'Remake\game\scripts\generated\legacy_media_route_catalog.gd')) =
        New-GdscriptMediaCatalog $mediaCatalog
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
