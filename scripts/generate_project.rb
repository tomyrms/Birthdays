#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "xcodeproj"

project_root = File.expand_path("..", __dir__)
ios_root = File.join(project_root, "ios")
project_path = File.join(ios_root, "Birthdays.xcodeproj")

build_number_path = File.join(project_root, "config", "build-number")
build_number = ENV["BIRTHDAYS_BUILD"] ||
               (File.exist?(build_number_path) ? File.read(build_number_path).strip : "21")
build_number = "21" if build_number.empty?

FileUtils.rm_rf(project_path)
project = Xcodeproj::Project.new(project_path)

app_group = project.main_group.new_group("Birthdays", "Birthdays")
widget_group = project.main_group.new_group("BirthdaysWidget", "BirthdaysWidget")
tests_group = project.main_group.new_group("BirthdaysTests", "BirthdaysTests")

def add_file(group, relative_path)
  parts = relative_path.split("/")
  filename = parts.pop
  destination = parts.reduce(group) do |current_group, part|
    current_group.groups.find { |child| child.display_name == part } || current_group.new_group(part, part)
  end
  destination.new_file(filename)
end

app_source_paths = Dir.glob(File.join(ios_root, "Birthdays", "**", "*.swift"))
  .map { |path| path.sub(File.join(ios_root, "Birthdays") + "/", "") }
  .sort
app_sources = app_source_paths.to_h { |path| [path, add_file(app_group, path)] }

assets_resource = add_file(app_group, "Resources/Assets.xcassets")
app_info = add_file(app_group, "Info.plist")
widget_source = add_file(widget_group, "BirthdaysWidget.swift")
widget_info = add_file(widget_group, "Info.plist")
test_source = add_file(tests_group, "BirthdayDateCalculatorTests.swift")

app_target = project.new_target(:application, "Birthdays", :ios, "17.0")
widget_target = project.new_target(:app_extension, "BirthdaysWidgetExtension", :ios, "17.0")
tests_target = project.new_target(:unit_test_bundle, "BirthdaysTests", :ios, "17.0")

app_sources.each_value { |reference| app_target.source_build_phase.add_file_reference(reference) }

# Les shaders sont compilés dans la bibliothèque Metal par défaut de l'app,
# que SwiftUI interroge via ShaderLibrary.
metal_sources = Dir.glob(File.join(ios_root, "Birthdays", "**", "*.metal"))
  .map { |path| path.sub(File.join(ios_root, "Birthdays") + "/", "") }
  .sort
metal_sources.each do |path|
  app_target.source_build_phase.add_file_reference(add_file(app_group, path))
end
app_target.resources_build_phase.add_file_reference(assets_resource)

widget_target.source_build_phase.add_file_reference(widget_source)
[
  "App/Theme.swift",
  "Core/Models/BirthdayModels.swift",
  "Core/Models/BirthdayDateCalculator.swift",
  "Core/Persistence/SharedBirthdayStorage.swift",
  "DesignSystem/BirthdayShaderBackground.swift"
].each do |path|
  widget_target.source_build_phase.add_file_reference(app_sources.fetch(path))
end

tests_target.source_build_phase.add_file_reference(test_source)
tests_target.add_dependency(app_target)

app_target.add_dependency(widget_target)
embed_extensions = app_target.new_copy_files_build_phase("Embed App Extensions")
embed_extensions.dst_subfolder_spec = "13"
widget_build_file = embed_extensions.add_file_reference(widget_target.product_reference, true)
widget_build_file.settings = { "ATTRIBUTES" => ["CodeSignOnCopy", "RemoveHeadersOnCopy"] }

common_settings = {
  "CLANG_ENABLE_MODULES" => "YES",
  # Numéro de build automatique. Réinstaller par sideload avec un numéro
  # identique laisse iOS conserver les composants en cache : l'app est bien
  # remplacée mais le widget continue d'afficher le rendu de la version d'avant.
  "CURRENT_PROJECT_VERSION" => build_number,
  "DEVELOPMENT_TEAM" => "ZE2545E5GV",
  "IPHONEOS_DEPLOYMENT_TARGET" => "17.0",
  "MARKETING_VERSION" => "1.18",
  # Sans les valeurs constantes émises par le compilateur, l'extracteur de
  # métadonnées ne voit aucun App Intent et Siri ignore l'app.
  "SWIFT_EMIT_CONST_VALUES" => "YES",
  "SWIFT_VERSION" => "5.0",
  "TARGETED_DEVICE_FAMILY" => "1"
}

app_target.build_configurations.each do |configuration|
  configuration.build_settings.merge!(common_settings)
  configuration.build_settings.merge!(
    "ASSETCATALOG_COMPILER_ACCENT_COLOR_NAME" => "AccentColor",
    "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES" => "AppIconBlue AppIconMint AppIconRose AppIconAmber AppIconGraphite",
    "ASSETCATALOG_COMPILER_APPICON_NAME" => "AppIcon",
    "CODE_SIGN_ENTITLEMENTS" => "Birthdays/Birthdays.entitlements",
    "CODE_SIGN_STYLE" => "Automatic",
    "GENERATE_INFOPLIST_FILE" => "NO",
    "INFOPLIST_FILE" => app_info.real_path.to_s.sub("#{ios_root}/", ""),
    "PRODUCT_BUNDLE_IDENTIFIER" => "ch.shulker.birthdays",
    "PRODUCT_NAME" => "$(TARGET_NAME)",
    "SUPPORTS_MACCATALYST" => "NO"
  )
end

widget_target.build_configurations.each do |configuration|
  configuration.build_settings.merge!(common_settings)
  configuration.build_settings.merge!(
    "APPLICATION_EXTENSION_API_ONLY" => "YES",
    "CODE_SIGN_ENTITLEMENTS" => "BirthdaysWidget/BirthdaysWidget.entitlements",
    "CODE_SIGN_STYLE" => "Automatic",
    "GENERATE_INFOPLIST_FILE" => "NO",
    "INFOPLIST_FILE" => widget_info.real_path.to_s.sub("#{ios_root}/", ""),
    "LD_RUNPATH_SEARCH_PATHS" => "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER" => "ch.shulker.birthdays.widget",
    "PRODUCT_NAME" => "$(TARGET_NAME)",
    "SKIP_INSTALL" => "YES",
    "SUPPORTS_MACCATALYST" => "NO"
  )
end

tests_target.build_configurations.each do |configuration|
  configuration.build_settings.merge!(common_settings)
  configuration.build_settings.merge!(
    "BUNDLE_LOADER" => "$(TEST_HOST)",
    "CODE_SIGN_STYLE" => "Automatic",
    "GENERATE_INFOPLIST_FILE" => "YES",
    "PRODUCT_BUNDLE_IDENTIFIER" => "ch.shulker.birthdays.tests",
    "PRODUCT_NAME" => "$(TARGET_NAME)",
    "TEST_HOST" => "$(BUILT_PRODUCTS_DIR)/Birthdays.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Birthdays"
  )
end

project.build_configurations.each do |configuration|
  configuration.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.add_test_target(tests_target)
scheme.set_launch_target(app_target)
scheme.save_as(project_path, "Birthdays", true)

puts "Projet généré : #{project_path}"
