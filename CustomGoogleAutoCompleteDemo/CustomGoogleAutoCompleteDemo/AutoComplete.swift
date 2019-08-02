
import Foundation
import UIKit
import CoreLocation
import GooglePlaces

//------------------------------------------------------------------------------------
// MARK:- Protocol
//------------------------------------------------------------------------------------
protocol GooglePlacesAutocompleteViewControllerDelegate: class {
    func viewController(didAutocompleteWith place: PlaceDetails)
}

//------------------------------------------------------------------------------------
// MARK:- Helper Class
//------------------------------------------------------------------------------------
private class GooglePlacesRequestHelpers {
    
    static func doRequest(_ urlString: String, params: [String: String], completion: @escaping (NSDictionary) -> Void) {
        var components = URLComponents(string: urlString)
        components?.queryItems = params.map { URLQueryItem(name: $0, value: $1) }
        
        guard let url = components?.url else { return }
        
        let task = URLSession.shared.dataTask(with: url, completionHandler: { (data, response, error) in
            if let error = error {
                print("GooglePlaces Error: \(error.localizedDescription)")
                return
            }
            
            guard let data = data, let response = response as? HTTPURLResponse else {
                print("GooglePlaces Error: No response from API")
                return
            }
            
            guard response.statusCode == 200 else {
                print("GooglePlaces Error: Invalid status code \(response.statusCode) from API")
                return
            }
            
            let object: NSDictionary?
            do {
                object = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? NSDictionary
            } catch {
                object = nil
                print("GooglePlaces Error")
                return
            }
            
            guard object?["status"] as? String == "OK" else {
                print("GooglePlaces API Error: \(object?["status"] ?? "")")
                return
            }
            
            guard let json = object else {
                print("GooglePlaces Parse Error")
                return
            }
            
            // Perform table updates on UI thread
            DispatchQueue.main.async {
                UIApplication.shared.isNetworkActivityIndicatorVisible = false
                completion(json)
            }
        })
        
        task.resume()
    }
    
    static func getPlaces(with parameters: [String: String], completion: @escaping ([Place]) -> Void) {
        var parameters = parameters
        if let deviceLanguage = deviceLanguage {
            parameters["language"] = deviceLanguage
        }
        doRequest(
            "https://maps.googleapis.com/maps/api/place/autocomplete/json",
            params: parameters,
            completion: {
                guard let predictions = $0["predictions"] as? [[String: Any]] else { return }
                completion(predictions.map { return Place(prediction: $0) })
        }
        )
    }
    
    static func getPlaceDetails(id: String, apiKey: String, completion: @escaping (PlaceDetails?) -> Void) {
        var parameters = [ "placeid": id, "key": apiKey ]
        if let deviceLanguage = deviceLanguage {
            parameters["language"] = deviceLanguage
        }
        doRequest(
            "https://maps.googleapis.com/maps/api/place/details/json",
            params: parameters,
            completion: { completion(PlaceDetails(json: $0 as? [String: Any] ?? [:])) }
        )
    }
    
    private static var deviceLanguage: String? {
        return (Locale.current as NSLocale).object(forKey: NSLocale.Key.languageCode) as? String
    }
}
//------------------------------------------------------------------------------------
// MARK:-
//------------------------------------------------------------------------------------
open class Place: NSObject {
    public let id: String
    public let mainAddress: String
    public let secondaryAddress: String
    
    override open var description: String {
        get { return "\(mainAddress), \(secondaryAddress)" }
    }
    
    init(id: String, mainAddress: String, secondaryAddress: String) {
        self.id = id
        self.mainAddress = mainAddress
        self.secondaryAddress = secondaryAddress
    }
    
    convenience init(prediction: [String: Any]) {
        let structuredFormatting = prediction["structured_formatting"] as? [String: Any]
        
        self.init(
            id: prediction["place_id"] as? String ?? "",
            mainAddress: structuredFormatting?["main_text"] as? String ?? "",
            secondaryAddress: structuredFormatting?["secondary_text"] as? String ?? ""
        )
    }
}

//------------------------------------------------------------------------------------
// MARK:-
//------------------------------------------------------------------------------------
open class PlaceDetails: CustomStringConvertible {
    public let formattedAddress: String
    open var name: String? = nil
    
    open var streetNumber: String? = nil
    open var route: String? = nil
    open var postalCode: String? = nil
    open var country: String? = nil
    open var countryCode: String? = nil
    
    open var locality: String? = nil
    open var subLocality: String? = nil
    open var administrativeArea: String? = nil
    open var administrativeAreaCode: String? = nil
    open var subAdministrativeArea: String? = nil
    
    open var coordinate: CLLocationCoordinate2D? = nil
    
    init?(json: [String: Any]) {
        guard let result = json["result"] as? [String: Any],
            let formattedAddress = result["formatted_address"] as? String
            else { return nil }
        
        self.formattedAddress = formattedAddress
        self.name = result["name"] as? String
        
        if let addressComponents = result["address_components"] as? [[String: Any]] {
            streetNumber = get("street_number", from: addressComponents, ofType: .short)
            route = get("route", from: addressComponents, ofType: .short)
            postalCode = get("postal_code", from: addressComponents, ofType: .long)
            country = get("country", from: addressComponents, ofType: .long)
            countryCode = get("country", from: addressComponents, ofType: .short)
            
            locality = get("locality", from: addressComponents, ofType: .long)
            subLocality = get("sublocality", from: addressComponents, ofType: .long)
            administrativeArea = get("administrative_area_level_1", from: addressComponents, ofType: .long)
            administrativeAreaCode = get("administrative_area_level_1", from: addressComponents, ofType: .short)
            subAdministrativeArea = get("administrative_area_level_2", from: addressComponents, ofType: .long)
        }
        
        if let geometry = result["geometry"] as? [String: Any],
            let location = geometry["location"] as? [String: Any],
            let latitude = location["lat"] as? CLLocationDegrees,
            let longitude = location["lng"] as? CLLocationDegrees {
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
    
    open var description: String {
        return "\nAddress: \(formattedAddress)\ncoordinate: (\(coordinate?.latitude ?? 0), \(coordinate?.longitude ?? 0))\n"
    }
}

extension PlaceDetails {
    
    enum ComponentType: String {
        case short = "short_name"
        case long = "long_name"
    }
    
    func get(_ component: String, from array: [[String: Any]], ofType: ComponentType) -> String? {
        return (array.first { ($0["types"] as? [String])?.contains(component) == true })?[ofType.rawValue] as? String
    }
}

//------------------------------------------------------------------------------------
// MARK:- AutoComplete Class
//------------------------------------------------------------------------------------
class AutoComplete:UIViewController {
    @IBOutlet weak var tblView      : UITableView!    
    
    var delegate                    : GooglePlacesAutocompleteViewControllerDelegate?
    var resultSearchController      = UISearchController()
    
    var placesClient                : GMSPlacesClient!
    let locationManager             = CLLocationManager()
    
    var places                      = [Place]() {
        didSet {
            self.tblView.reloadData()
        }
    }
    
    override func viewDidLoad() {
        tblView.delegate = self
        tblView.dataSource = self
        
        self.resultSearchController = ({
            let controller = UISearchController(searchResultsController: nil)
            controller.searchResultsUpdater = self
            controller.dimsBackgroundDuringPresentation = false
            controller.searchBar.sizeToFit()
            controller.searchBar.barStyle = UIBarStyle.black
            controller.searchBar.barTintColor = UIColor.white
            controller.searchBar.backgroundColor = UIColor.clear
            self.tblView.tableHeaderView = controller.searchBar
            return controller
        })()
        
        self.tblView.tableFooterView = addButton()
        
        locationManager.requestAlwaysAuthorization()
        locationManager.requestWhenInUseAuthorization()
        
        if CLLocationManager.locationServicesEnabled() {
            locationManager.delegate = self
            placesClient = GMSPlacesClient.shared()
        }
    }
    
    func addButton() -> UIView {
        
        let vieww = UIView(frame: CGRect(x: 0, y: 5 , width: self.tblView.frame.width - 10, height: 50))
        let btn = UIButton(frame: CGRect(x: 15, y: 10, width:  vieww.frame.width - 15 , height: 40))
        
        btn.setTitle("Current Location", for: .normal)
        btn.setImage(UIImage(named: "location"), for: .normal)
        btn.setTitleColor(UIColor.black, for: .normal)
        btn.backgroundColor = UIColor.white
        btn.contentHorizontalAlignment = .left
        
        btn.layer.shadowColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.25).cgColor
        btn.layer.shadowOffset = CGSize(width: 2.5, height: 2.5)
        btn.layer.shadowOpacity = 1.0
        btn.layer.shadowRadius = 0.0
        btn.layer.masksToBounds = false
        btn.layer.cornerRadius = 4.0
        btn.layer.borderColor = UIColor.groupTableViewBackground.cgColor
        btn.layer.borderWidth = 0.5
        
        btn.imageEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        btn.titleEdgeInsets = UIEdgeInsets(top: 8, left: 20, bottom: 8, right: 15)
        
        btn.addTarget(self, action: #selector(fetchCurrentLocation), for: .touchUpInside)
        
        vieww.addSubview(btn)
        return vieww
    }
    
    @objc func fetchCurrentLocation(){
        locationManager.startUpdatingLocation()
    }
}

//------------------------------------------------------------------------------------
// MARK:- Tableview Delegate methods
//------------------------------------------------------------------------------------
extension AutoComplete : UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return places.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tblView.dequeueReusableCell(withIdentifier: "cell"
            , for: indexPath)
        cell.textLabel?.text = places[indexPath.row].description
        cell.detailTextLabel?.text = places[indexPath.row].mainAddress
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let place = places[indexPath.row]
        
        GooglePlacesRequestHelpers
            .getPlaceDetails(id: place.id, apiKey: GoogleMapsAPIServerKey) { [unowned self] in
                guard let value = $0 else { return }
                self.delegate?.viewController(didAutocompleteWith: value)
                self.resultSearchController.isActive = false
                self.navigationController?.popViewController(animated: true)
        }
    }
}

//------------------------------------------------------------------------------------
// MARK:- Searchbar Delegate methods
//------------------------------------------------------------------------------------
extension AutoComplete: UISearchBarDelegate, UISearchResultsUpdating {
    
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        guard !searchText.isEmpty else { places = []; return }
        let parameters = [
            "input": searchText,
            "key": GoogleMapsAPIServerKey
        ]
        GooglePlacesRequestHelpers.getPlaces(with: parameters) {
            self.places = $0
        }
    }
    
    public func updateSearchResults(for searchController: UISearchController) {
        
        if searchController.searchBar.text!.isEmpty {
            self.tblView.tableFooterView = addButton()
            self.tblView.layoutIfNeeded()
        }
        
        guard let searchText = searchController.searchBar.text, !searchText.isEmpty else { places = []; return }
        let parameters = [
            "input": searchText,
            "key": GoogleMapsAPIServerKey
        ]
        
        GooglePlacesRequestHelpers.getPlaces(with: parameters) {
            self.places = $0
            self.tblView.tableFooterView = UIView()
        }
    }
}

//------------------------------------------------------------------------------------
// MARK:- CLLocationManagerDelegate
//------------------------------------------------------------------------------------
extension AutoComplete : CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if locations.first != nil {
            locationManager.stopUpdatingLocation()
            placesClient.currentPlace(callback: { (placeLikelihoods, error) -> Void in
                if let error = error {
                    // TODO: Handle the error.
                    print("Current Place error: \(error.localizedDescription)")
                    return
                }
                
                // Get likely places and add to the list.
                if let likelihoodList = placeLikelihoods {
                    if let place = likelihoodList.likelihoods.first?.place {
                        self.locationManager.stopUpdatingLocation()
                        if let placeId = place.placeID {
                            GooglePlacesRequestHelpers
                                .getPlaceDetails(id: placeId, apiKey: GoogleMapsAPIServerKey) { [unowned self] in
                                    guard let value = $0 else { return }
                                    self.delegate?.viewController(didAutocompleteWith: value)
                                    self.resultSearchController.isActive = false
                                    self.navigationController?.popViewController(animated: true)
                            }
                        }
                    }
                }
                
            })
        }
    }
}
