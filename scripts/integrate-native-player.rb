require 'xcodeproj'
require 'fileutils'

project_path = 'ios/App/App.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |item| item.name == 'App' }
abort 'App target not found in generated Capacitor project' unless target

package_url = 'https://github.com/superuser404notfound/AetherEngine'
package = project.root_object.package_references.find do |ref|
  ref.respond_to?(:repositoryURL) && ref.repositoryURL == package_url
end

unless package
  package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  package.repositoryURL = package_url
  package.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => '7.0.0' }
  project.root_object.package_references << package
end

unless target.package_product_dependencies.any? { |dep| dep.product_name == 'AetherEngine' }
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.package = package
  dependency.product_name = 'AetherEngine'
  target.package_product_dependencies << dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
end

app_group = project.main_group.find_subpath('App', true)
%w[AetherPlayerPlugin.swift VYROBridgeViewController.swift].each do |filename|
  source_path = File.expand_path("../native/ios/#{filename}", __dir__)
  destination = File.expand_path("ios/App/App/#{filename}")
  FileUtils.cp(source_path, destination)
  reference = app_group.files.find { |file| file.path == filename } || app_group.new_file(filename)
  target.source_build_phase.add_file_reference(reference, true) unless target.source_build_phase.files_references.include?(reference)
end

storyboard = 'ios/App/App/Base.lproj/Main.storyboard'
xml = File.read(storyboard)
xml.sub!('customClass="CAPBridgeViewController" customModule="Capacitor"', 'customClass="VYROBridgeViewController" customModule="App"')
abort 'Could not locate Capacitor bridge controller in Main.storyboard' unless xml.include?('VYROBridgeViewController')
File.write(storyboard, xml)

project.save
puts 'AetherEngine and VYRO native bridge added to generated iOS project.'
