Pod::Spec.new do |s|
  s.name             = 'flutter_widget_recorder'
  s.version          = '0.0.1'
  s.summary          = 'A Flutter plugin for recording widget animation using RepaintBoundary widget and sending it to the platform plugin for conversion to video'
  s.description      = <<-DESC
A Flutter plugin for recording widget animation using RepaintBoundary widget and sending it to the platform plugin for conversion to video
                       DESC
  s.homepage         = 'https://github.com/RuslanTsitser/flutter_widget_recorder'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ruslan Tsitser' => 'cicerro96@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
