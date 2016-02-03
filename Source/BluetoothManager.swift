//
//  BluetoothManager.swift
//  Swift-LightBlue
//
//  Created by Pluto Y on 16/1/3.
//  Copyright © 2016年 Pluto-y. All rights reserved.
//

import CoreBluetooth

public class BluetoothManager : NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    var _manager : CBCentralManager?
    var delegate : BluetoothDelegate?
    private(set) var connected = false
    private var timeoutMonitor : NSTimer? /// Timeout monitor of connect to peripheral
    private var interrogateMonitor : NSTimer? /// Timeout monitor of interrogate the peripheral
    private var isConnecting = false
    var logs = [String]()
    private(set) var connectedPeripheral : CBPeripheral?
    private(set) var connectedServices : [CBService]?
    
    /// Save the single instance
    static private var instance : BluetoothManager {
        struct Static {
            static var onceToken : dispatch_once_t = 0
            static var sharedInstance : BluetoothManager? = nil
        }
        dispatch_once(&Static.onceToken) { () -> Void in
            Static.sharedInstance = BluetoothManager()
            Static.sharedInstance?.initCBCentralManager()
        }
        return Static.sharedInstance!
    }
    
    // MARK: Custom functions
    /**
    Initialize CBCentralManager instance
    */
    func initCBCentralManager() {
        var dic : [String : AnyObject] = Dictionary()
        dic[CBCentralManagerOptionShowPowerAlertKey] = false
        _manager = CBCentralManager(delegate: self, queue:nil, options: dic)
    }
    
    /**
     Singleton pattern method
     
     - returns: Bluetooth single instance
     */
    static func getInstance() -> BluetoothManager {
        return instance
    }
    
    /**
     The method provides for starting scan near by peripheral
     */
    func startScanPeripheral() {
        _manager?.scanForPeripheralsWithServices(nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey:true])
    }
    
    /**
     The method provides for stopping scan near by peripheral
     */
    func stopScanPeripheral() {
        _manager?.stopScan()
    }
    
    /**
     The method provides for connecting the special peripheral
     
     - parameter peripher: The peripheral you want to connect
     */
    func connectPeripheral(peripheral: CBPeripheral) {
        if !isConnecting {
            isConnecting = true
            _manager?.connectPeripheral(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey : true])
            timeoutMonitor = NSTimer.scheduledTimerWithTimeInterval(2.0, target: self, selector: "connectTimeout:", userInfo: peripheral, repeats: false)
        }
    }
    
    /**
     The method provides for disconnecting with the peripheral which has connected
     */
    func disconnectPeripheral() {
        if connectedPeripheral != nil {
            _manager?.cancelPeripheralConnection(connectedPeripheral!)
            startScanPeripheral()
            connectedPeripheral = nil
        }
    }
    
    /**
     The method provides for the user who want to obtain the descriptor
     
     - parameter characteristic: The character which user want to obtain descriptor
     */
    func discoverDescriptor(characteristic: CBCharacteristic) {
        if connectedPeripheral != nil  {
            connectedPeripheral?.discoverDescriptorsForCharacteristic(characteristic)
        }
    }
    
    /**
     The method is invoked when connect peripheral is timeout
     
     - parameter timer: The timer touch off this selector
     */
    @objc private func connectTimeout(timer : NSTimer) {
        if isConnecting {
            isConnecting = false
            connectPeripheral((timer.userInfo as! CBPeripheral))
            timeoutMonitor = nil
        }
    }
    
    /**
     This method is invoked when interrogate peripheral is timeout
     
     - parameter timer: The timer touch off this selector
     */
    @objc private func integrrogateTimeout(timer: NSTimer) {
        disconnectPeripheral()
        delegate?.didFailedToInterrogate?((timer.userInfo as! CBPeripheral))
    }
    
    /**
     This method provides for discovering the characteristics.
     */
    func discoverCharacteristics() {
        if connectedPeripheral == nil {
            return
        }
        let services = connectedPeripheral!.services
        if services == nil || services!.count < 1 { // Validate service array
            return;
        }
        for service in services! {
            connectedPeripheral!.discoverCharacteristics(nil, forService: service)
        }
    }
    
    /**
     Read characteristic value from the peripheral
     
     - parameter characteristic: The characteristic which user should 
     */
    func readValueForCharacteristic(characteristic: CBCharacteristic) {
        if connectedPeripheral == nil {
            return
        }
        connectedPeripheral?.readValueForCharacteristic(characteristic)
    }
    
    // MARK: Delegate
    /**
    Invoked whenever the central manager's state has been updated.
     */
    public func centralManagerDidUpdateState(central: CBCentralManager) {
        switch central.state {
        case .PoweredOff:
            print("State : Powered Off")
        case .PoweredOn:
            print("State : Powered On")
        case .Resetting:
            print("State : Resetting")
        case .Unauthorized:
            print("State : Unauthorized")
        case .Unknown:
            print("State : Unknown")
        case .Unsupported:
            print("State : Unsupported")
        }
        delegate?.didUpdateState?(central.state)
    }
    
    /**
     This method is invoked while scanning, upon the discovery of peripheral by central
     
     - parameter central:           The central manager providing this update.
     - parameter peripheral:        The discovered peripheral.
     - parameter advertisementData: A dictionary containing any advertisement and scan response data.
     - parameter RSSI:              The current RSSI of peripheral, in dBm. A value of 127 is reserved and indicates the RSSI
     *								was not available.
     */
    public func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        print("Bluetooth Manager --> didDiscoverPeripheral, RSSI:\(RSSI)")
        delegate?.didDiscoverPeripheral?(peripheral, advertisementData: advertisementData, RSSI: RSSI)
    }
    
    /**
     This method is invoked when a connection succeeded
     
     - parameter central:    The central manager providing this information.
     - parameter peripheral: The peripheral that has connected.
     */
    public func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        print("Bluetooth Manager --> didConnectPeripheral")
        isConnecting = false
        if timeoutMonitor != nil {
            timeoutMonitor!.invalidate()
            timeoutMonitor = nil
        }
        connected = true
        connectedPeripheral = peripheral
        delegate?.didConnectedPeripheral?(peripheral)
        stopScanPeripheral()
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        interrogateMonitor = NSTimer.scheduledTimerWithTimeInterval(5.0, target: self, selector: Selector("integrrogateTimeout:"), userInfo: peripheral, repeats: false)
    }
    
    /**
     This method is invoked where a connection failed.
     
     - parameter central:    The central manager providing this information.
     - parameter peripheral: The peripheral that you tried to connect.
     - parameter error:      The error infomation about connecting failed.
     */
    public func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        print("Bluetooth Manager --> didFailToConnectPeripheral")
        isConnecting = false
        if timeoutMonitor != nil {
            timeoutMonitor!.invalidate()
            timeoutMonitor = nil
        }
        connected = false
        delegate?.failToConnectPeripheral?(peripheral, error: error!)
    }
    
    /**
     The method is invoked where services were discovered.
     
     - parameter peripheral: The peripheral with service informations.
     - parameter error:      Errot message when discovered services.
     */
    public func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        print("Bluetooth Manager --> didDiscoverServices")
        connectedPeripheral = peripheral
        if error != nil {
            print("Bluetooth Manager --> Discover Services Error, error:\(error?.localizedDescription)")
            return ;
        }
        
        // If discover services, then invalidate the timeout monitor
        if interrogateMonitor != nil {
            interrogateMonitor?.invalidate()
            interrogateMonitor = nil
        }
        
        self.delegate?.didDiscoverServices?(peripheral)
    }
    
    /**
     The method is invoked where characteristics were discovered.
     
     - parameter peripheral: The peripheral provide this information
     - parameter service:    The service included the characteristics.
     - parameter error:      If an error occurred, the cause of the failure.
     */
    public func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
        print("Bluetooth Manager --> didDiscoverCharacteristicsForService")
        if error != nil {
            print("Bluetooth Manager --> Fail to discover characteristics! Error: \(error?.localizedDescription)")
            delegate?.didFailToDiscoverCharacteritics?(error!)
            return
        }
        delegate?.didDiscoverCharacteritics?(service)
    }
    
    /**
     This method is invoked when the peripheral has found the descriptor for the characteristic
     
     - parameter peripheral:     The peripheral providing this information
     - parameter characteristic: The characteristic which has the descriptor
     - parameter error:          The error message
     */
    public func peripheral(peripheral: CBPeripheral, didDiscoverDescriptorsForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        print("Bluetooth Manager --> didDiscoverDescriptorsForCharacteristic")
        if error != nil {
            print("Bluetooth Manager --> Fail to discover descriptor for characteristic Error:\(error?.localizedDescription)")
            delegate?.didFailToDiscoverDescriptors?(error!)
            return
        }
        delegate?.didDiscoverDescriptors?(characteristic)
    }
    
    /**
     This method is invoked when the peripheral has been disconnected.
     
     - parameter central:    The central manager providing this information
     - parameter peripheral: The disconnected peripheral
     - parameter error:      The error message
     */
    public func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        print("Bluetooth Manager --> didDisconnectPeripheral")
        connected = false
        self.delegate?.didDisconnectPeripheral?(peripheral)
    }
    
    /**
     Thie method is invoked when the user call the peripheral.readValueForCharacteristic
     
     - parameter peripheral:     The periphreal which call the method
     - parameter characteristic: The characteristic with the new value
     - parameter error:          The error message
     */
    public func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        print("Bluetooth Manager --> didUpdateValueForCharacteristic")
        if error != nil {
            print("Bluetooth Manager --> Failed to read value for the characteristic. Error:\(error!.localizedDescription)")
            delegate?.didFailToReadValueForCharacteristic?(error!)
            return
        }
        delegate?.didReadValueForCharacteristic?(characteristic)
        
    }
    
}
