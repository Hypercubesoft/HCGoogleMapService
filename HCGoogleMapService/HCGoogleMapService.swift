//
//  HCGoogleMapService.swift
//
//  Created by Hypercube on 10/5/17.
//  Copyright © 2017 Hypercube. All rights reserved.
//

import Foundation
import GoogleMaps
import GooglePlaces
import HCKalmanFilter
import HCFramework
import HCLocationManager

open class HCGoogleMapService: NSObject
{
    /// Google Maps API Key
    private var GOOGLE_MAPS_API_KEY : String = ""
    
    private static var isRecordingLocation: Bool = false
    open static var useKalmanFilterForTracking : Bool = false
    
    private var lastLocation: CLLocation? = nil
    private var lastTrackingLocation: CLLocation? = nil
    
    private var paths: [GMSMutablePath] = []
    private var pathLengths: [Float] = []
    private var startTimes: [Date] = []
    private var endTimes: [Date] = []
    
    private var kalmanFilter: HCKalmanAlgorithm?
    private var resetKalmanFilter: Bool = false
    private var isFirstLocation: Bool = true
    
    // Parameters for elimination distortion of initial GPS points when we use HCKalmanFilter
    open static var minTimeForGetPoint = 0.5
    open static var maxTimeForGetPoint = 8.0
    open static var maxAccuracy = 25.0
    open static var minDistance = 0.1
    
    private var lastCorrectPointTime:Date = Date()
    
    open static let sharedService: HCGoogleMapService = {
        let instance = HCGoogleMapService()
        
        return instance
    }()
    
    // MARK: - Setup Service
    
    /// Configure GoogleMapService with API Keys
    open func setupGoogleMapService(googleMapApiKey: String)
    {
        GOOGLE_MAPS_API_KEY = googleMapApiKey
        
        GMSServices.provideAPIKey(GOOGLE_MAPS_API_KEY)
        GMSPlacesClient.provideAPIKey(GOOGLE_MAPS_API_KEY)
        
        HCAppNotify.observeNotification(self, selector: #selector(locationUpdated(notification:)), name:"HCLocationUpdated")
    }
    
    // MARK: - Map setup and manipulation.
    
    /// Set GoogleMap Camera in mapView on specified location (latitude and longitude)
    ///
    /// - Parameters:
    ///   - lat: Camera latitude location
    ///   - long: Camera longitude location
    ///   - zoom: Camera zoom param. Default value is set to 15.0.
    ///   - mapView: GMSMapView map view
    open class func setCamera(_ lat: CLLocationDegrees, long: CLLocationDegrees, zoom: Float = 15.0, mapView: GMSMapView)
    {
        mapView.camera = GMSCameraPosition.camera(withLatitude: lat, longitude: long, zoom: zoom)
    }
    
    /// Set GoogleMap Camera in mapView on current location
    ///
    /// - Parameters:
    ///   - mapView: GMSMapView map view
    ///   - zoom: Camera zoom param. Default value is set to 15.0.
    open class func setCameraToCurrentLocation(_ mapView: GMSMapView, zoom: Float = 15.0)
    {
        let currentLocation = HCLocationManager.sharedManager.getCurrentLocation()
        mapView.camera = GMSCameraPosition.camera(withLatitude: currentLocation!.coordinate.latitude,
                                                  longitude: currentLocation!.coordinate.longitude, zoom: zoom)
    }
    
    // MARK: - Map Markers
    
    /// Create Marker on GMSMapView on specified location (latitude and longitude) and specified marker icon
    ///
    /// - Parameters:
    ///   - lat: Marker Latitude
    ///   - long:  Marker Longitude
    ///   - mapView: GMSMapView map view
    ///   - iconImage: Marker icon image. Default value is empty String, in this case, marker has default marker icon.
    open class func createMarker(lat: CLLocationDegrees, long: CLLocationDegrees, mapView: GMSMapView, iconImage: String = "")
    {
        // Creates a marker in the center of the map.
        let marker = GMSMarker()
        marker.position = CLLocationCoordinate2D(latitude: lat, longitude: long)
        
        if iconImage != "" {
            marker.icon = UIImage(named: iconImage)
        }
        
        marker.map = mapView
    }
    
    /// Create Marker on GMSMapView on current location, and specified marker icon
    ///
    /// - Parameters:
    ///   - mapView: GMSMapView map view
    ///   - iconImage: Marker icon image. Default value is empty String, in this case, marker has default marker icon.
    open class func createMarkerCurrentPosition(_ mapView: GMSMapView, iconImage: String = "")
    {
        let currentLocation = HCLocationManager.sharedManager.getCurrentLocation()
        mapView.clear()
        createMarker(lat: currentLocation!.coordinate.latitude,
                     long: currentLocation!.coordinate.longitude,
                     mapView: mapView,
                     iconImage: iconImage)
    }
    
    // MARK: - User Tracking
    
    /// Create and append new path on paths array
    private class func startNewPath()
    {
        sharedService.pathLengths.append(0)
        sharedService.paths.append(GMSMutablePath())
    }
    
    /// Append new point to last path in paths array
    ///
    /// - Parameters:
    ///   - lat: New Point Latitude
    ///   - long: New Point Longitude
    open class func addNewPointToLastPath(lat: CLLocationDegrees, long: CLLocationDegrees)
    {
        if let path = sharedService.paths.last {
            path.add(CLLocationCoordinate2D(latitude: lat, longitude: long))
        }
    }
    
    /// Start Tracking, create new path and start measure path time
    ///
    /// - Parameter isFirstPath: Indicate is this first path during tracking. Default value is false.
    open class func startTracking(_ isFirstPath: Bool = false)
    {
        isRecordingLocation = true
        sharedService.lastCorrectPointTime = Date()
        
        if HCGoogleMapService.useKalmanFilterForTracking {
            if sharedService.kalmanFilter != nil {
                sharedService.resetKalmanFilter = true
            }
        }
        
        // Start new path
        startNewPath()
        
        // Add to the last path if needed.
        if let last = sharedService.lastLocation {
            if isFirstPath {
                addNewPointToLastPath(lat: last.coordinate.latitude,
                                      long: last.coordinate.longitude) }
        }
        
        // Set current time for this path.
        let currentTime = Date()
        sharedService.startTimes.append(currentTime)
    }
    
    /// Stop Tracking
    open class func endTracking()
    {
        isRecordingLocation = false
        
        let currentTime = Date()
        sharedService.endTimes.append(currentTime)
    }
    
    /// Calculate past time during all tracking paths
    ///
    /// - Returns: Past time during all tracking paths
    open class func getTrackingTime() -> TimeInterval
    {
        var timePassed: TimeInterval = 0
        if sharedService.startTimes.count > 1 && sharedService.endTimes.count > 0 {
            for i in 0...sharedService.startTimes.count - 2 {
                timePassed.add(sharedService.endTimes[i].timeIntervalSince(sharedService.startTimes[i]))
            }
        }
        
        if sharedService.startTimes.count > 0 {
            timePassed.add(Date().timeIntervalSince(sharedService.startTimes.last!)) }
        
        return timePassed
    }
    
    
    /// Calculate distance during all tracking paths
    ///
    /// - Parameter inMiles: Whether the distance returns in miles. Default value is false.
    /// - Returns: Distance during all tracking paths
    open class func getTrackingDistance(inMiles: Bool = false) -> Float
    {
        var distance: Float = 0
        for num in sharedService.pathLengths {
            distance += num
        }
        
        if inMiles
        {
            distance = distance * 0.621371
        }
        
        return distance
    }
    
    /// Reset all arrays, related to user tracking
    open class func resetAll() {
        sharedService.pathLengths.removeAll()
        sharedService.paths.removeAll()
        sharedService.startTimes.removeAll()
        sharedService.endTimes.removeAll()
    }
    
    // MARK: - Create, Update and Draw polyline on map.
    
    /// Draw All Paths Polylines on MapView
    ///
    /// - Parameters:
    ///   - mapView: GMSMapView map view
    ///   - strokeColor: Paths lines stroke color
    ///   - startPinIcon: Start Marker icon image. Default value is empty String, in this case, Start marker has default marker icon.
    ///   - endPinIcon: End Marker icon image. Default value is empty String, in this case, End marker has same icon like start marker.
    open class func drawAllPolylinesOnMap(_ mapView: GMSMapView, strokeColor: UIColor, startPinIcon: String = "", endPinIcon: String = "")
    {
        var endIcon = endPinIcon
        if endPinIcon == ""
        {
            endIcon = startPinIcon
        }
        
        for path in sharedService.paths
        {
            drawPolyline(mapView, path: path, strokeColor: strokeColor)
            createMarker(lat: path.coordinate(at: 0).latitude, long: path.coordinate(at: 0).longitude, mapView: mapView, iconImage: startPinIcon)
            if path.count() > 0 {
                createMarker(lat: path.coordinate(at: path.count() - 1).latitude, long: path.coordinate(at: path.count() - 1).longitude, mapView: mapView, iconImage: endIcon)
            }
        }
    }
    
    /// Draw One Path Polyline on MapView
    ///
    /// - Parameters:
    ///   - mapView: GMSMapView map view
    ///   - path: GMSMutablePath object to draw
    ///   - strokeColor: Path line stroke color
    ///   - strokeWidth: ath line stroke width
    open class func drawPolyline(_ mapView: GMSMapView, path: GMSMutablePath, strokeColor: UIColor, strokeWidth: CGFloat = 5.0)
    {
        let polyline = GMSPolyline(path: path)
        polyline.strokeColor = strokeColor
        polyline.strokeWidth = strokeWidth
        polyline.map = mapView
    }
    
    // MARK: - HCLocationManager Observer Function
    
    /// A function that responds to locationUpdated Notification from HCLocationManager
    func locationUpdated(notification:Notification) {
        
        var myCurrentLocation = notification.object as! CLLocation
        
        lastLocation = myCurrentLocation
        
        // Check if tracking is active
        if HCGoogleMapService.isRecordingLocation {
            
            // Check if tracking use Kalman Filter
            if HCGoogleMapService.useKalmanFilterForTracking
            {
                if kalmanFilter == nil {
                    
                    // If kalmanFilter is nil, setup kalmanFilter object first
                    self.lastCorrectPointTime = myCurrentLocation.timestamp
                    self.kalmanFilter = HCKalmanAlgorithm(initialLocation: myCurrentLocation)
                    
                    // If horizontalAccuracy of current location is less than maxAccuracy parameter, then add current location to last path locations array. Otherwise reset KalmanFilter.
                    if myCurrentLocation.horizontalAccuracy < HCGoogleMapService.maxAccuracy {
                        if let path = paths.last {
                            path.replaceCoordinate(at: 0, with: CLLocationCoordinate2D(latitude: myCurrentLocation.coordinate.latitude,
                                                                                       longitude: myCurrentLocation.coordinate.longitude))
                        }
                    } else {
                        self.resetKalmanFilter = true
                    }
                }
                else
                {
                    if let kalmanFilter = self.kalmanFilter
                    {
                        // If necessary reset kalmanFilter object
                        if self.resetKalmanFilter == true
                        {
                            // If horizontalAccuracy of current location is less than maxAccuracy parameter, then reset kalmanFilter object and add current location to last path locations array.
                            if myCurrentLocation.horizontalAccuracy < HCGoogleMapService.maxAccuracy
                            {
                                kalmanFilter.resetKalman(newStartLocation: myCurrentLocation)
                                self.resetKalmanFilter = false
                                
                                self.lastCorrectPointTime = myCurrentLocation.timestamp
                                
                                if let path = paths.last {
                                    path.replaceCoordinate(at: 0, with: CLLocationCoordinate2D(latitude: myCurrentLocation.coordinate.latitude,
                                                                                               longitude: myCurrentLocation.coordinate.longitude))
                                }
                            }
                            // If reading time of the last correct point exceeds maxTimeForGetPoint parameter, trigger LowAccuracy Notification. Otherwise stop current, and start the next iteration.
                            else if myCurrentLocation.timestamp.timeIntervalSince(self.lastCorrectPointTime) > HCGoogleMapService.maxTimeForGetPoint {
                                HCAppNotify.postNotification("HCTriggerLowAccuracy")
                                return
                            } else {
                                return
                            }
                        }
                        else
                        {
                             // If horizontalAccuracy of current location is less than maxAccuracy parameter and reading time of the last correct point exceeds minTimeForGetPoint parameter, process current location with KalmanFilter and add processed location to last path locations array.
                            if myCurrentLocation.horizontalAccuracy < HCGoogleMapService.maxAccuracy && myCurrentLocation.timestamp.timeIntervalSince(self.lastCorrectPointTime) > HCGoogleMapService.minTimeForGetPoint
                            {
                                let kalmanLocation = kalmanFilter.processState(currentLocation: myCurrentLocation)
                                self.lastCorrectPointTime = myCurrentLocation.timestamp
                                
                                HCGoogleMapService.addNewPointToLastPath(lat: kalmanLocation.coordinate.latitude,
                                                                         long: kalmanLocation.coordinate.longitude)
                                
                                myCurrentLocation = kalmanLocation
                            }
                            else
                            {
                                // Otherwise if reading time of the last correct point exceeds maxTimeForGetPoint parameter, trigger LowAccuracy Notification.
                                if myCurrentLocation.timestamp.timeIntervalSince(self.lastCorrectPointTime) > HCGoogleMapService.maxTimeForGetPoint
                                {
                                    HCAppNotify.postNotification("HCTriggerLowAccuracy")
                                }
                                return
                            }
                        }
                    }
                }
            }
            else
            {
                // Tracking not use Kalman Filter, then only add current location to last path locations array
                HCGoogleMapService.addNewPointToLastPath(lat: myCurrentLocation.coordinate.latitude,
                                                         long: myCurrentLocation.coordinate.longitude)
            }
            
            if lastTrackingLocation != nil {
                
                let distance = myCurrentLocation.distance(from: lastTrackingLocation!)
                
                // If distance from lastTrackingLocation to current location is less then minDistance, return.
                if distance < HCGoogleMapService.minDistance
                {
                    return
                }
                
                // Otherwise if tracking is active, add distance to last pathLengths array
                if HCGoogleMapService.isRecordingLocation {
                    pathLengths[pathLengths.count - 1] += Float(distance)
                }
            }
            
            // Save current location to lastTrackingLocation
            lastTrackingLocation = myCurrentLocation
        }
        else
        {
            lastTrackingLocation = nil
            lastLocation = myCurrentLocation
        }
    }
}
