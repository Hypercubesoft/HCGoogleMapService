Pod::Spec.new do |s|

s.platform = :ios
s.name             = "HCGoogleMapService"
s.version          = "1.0.0"
s.summary          = "These are internal files we use in our company."

s.description      = <<-DESC
These are internal files we use in our company. We will not add new functions on request.
DESC

s.homepage         = "https://github.com/Hypercubesoft/HCGoogleMapService"
s.license          = { :type => "MIT", :file => "LICENSE" }
s.author           = { "Hypercubesoft" => "office@hypercubesoft.com" }
s.source           = { :git => "https://github.com/Hypercubesoft/HCGoogleMapService.git", :tag => "#{s.version}"}

s.ios.deployment_target = "9.0"
s.source_files = "HCGoogleMapService", "HCGoogleMapService/*"

s.dependency 'GoogleMaps'
s.dependency 'GooglePlaces'
s.dependency 'HCKalmanFilter'
s.dependency 'HCFramework'
s.dependency 'HCLocationManager'

end