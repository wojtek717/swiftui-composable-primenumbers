//
//  ContentView.swift
//  SwiftUIPrimeNumbers
//
//  Created by Wojciech Konury on 13/03/2021.
//

import SwiftUI

struct WolframAlphaResult: Decodable {
    let queryresult: QueryResult
    
    struct QueryResult: Decodable {
        let pods: [Pod]
        
        struct Pod: Decodable {
            let primary: Bool?
            let subpods: [SubPod]
            
            struct SubPod: Decodable {
                let plaintext: String
            }
        }
    }
}

func wolframAlpha(query: String, callback: @escaping (WolframAlphaResult?) -> Void) -> Void {
    var components = URLComponents(string: "https://api.wolframalpha.com/v2/query")!
    components.queryItems = [
        URLQueryItem(name: "input", value: query),
        URLQueryItem(name: "format", value: "plaintext"),
        URLQueryItem(name: "output", value: "JSON"),
        URLQueryItem(name: "appid", value: "KQH6KK-62AETKJEEA"),
    ]
    
    URLSession.shared.dataTask(with: components.url(relativeTo: nil)!) { data, response, error in
        callback(
            data
                .flatMap { try? JSONDecoder().decode(WolframAlphaResult.self, from: $0) }
        )
    }
    .resume()
}

func nthPrime(_ n: Int, callback: @escaping (Int?) -> Void) -> Void {
    wolframAlpha(query: "prime \(n)") { result in
        callback(
            result
                .flatMap {
                    $0.queryresult
                        .pods
                        .first(where: { $0.primary == .some(true) })?
                        .subpods
                        .first?
                        .plaintext
                }
                .flatMap(Int.init)
        )
    }
}

struct AppState {
  var count = 0
  var favoritePrimes: [Int] = []
  var loggedInUser: User? = nil
  var activityFeed: [Activity] = []

  struct Activity {
    let timestamp: Date
    let type: ActivityType

    enum ActivityType {
      case addedFavoritePrime(Int)
      case removedFavoritePrime(Int)
    }
  }

  struct User {
    let id: Int
    let name: String
    let bio: String
  }
}

extension AppState {
    var favoritePrimesState: FavoritePrimesState {
        get {
            FavoritePrimesState(
                favoritePrimes: self.favoritePrimes,
                activityFeed: self.activityFeed)
        }
        set {
            self.favoritePrimes = newValue.favoritePrimes
            self.activityFeed = newValue.activityFeed
        }
    }
}

struct FavoritePrimesState {
  var favoritePrimes: [Int]
  var activityFeed: [AppState.Activity]
}

final class Store<Value, Action>: ObservableObject {
    let reducer: (inout Value, Action) -> Void
    @Published var value: Value
    
    init(initialValue: Value, reducer: @escaping (inout Value, Action) -> Void ) {
        self.reducer = reducer
        self.value = initialValue
    }
    
    func send(_ action: Action) {
        self.reducer(&self.value, action)
    }
}

enum CounterAction {
    case decrTapped
    case incrTapped
}

enum PrimeModalAction {
    case saveFavoritePrimeTapped
    case removeFavoritePrimeTapped
}

enum FavoritePrimesAction {
    case deleteFavoritePrimes(IndexSet)
}

enum AppAction {
    case counter(CounterAction)
    case primeModal(PrimeModalAction)
    case favoritePrimes(FavoritePrimesAction)
}

func counterReducer(state: inout Int, action: AppAction) {
    switch action {
    case .counter(.decrTapped):
        state -= 1
    case .counter(.incrTapped):
        state += 1
    default:
        break
    }
}

func primeModalReducer(state: inout AppState, action: AppAction) {
    switch action {
    case .primeModal(.saveFavoritePrimeTapped):
        state.favoritePrimes.append(state.count)
    case .primeModal(.removeFavoritePrimeTapped):
        state.favoritePrimes.removeAll {
            $0 == state.count
        }
    default:
        break
    }
}

struct FavoritePrimes {
    var favoritePrimes: [Int]
}

func favoritePrimesReducer(state: inout FavoritePrimesState, action: AppAction) {
    switch action {
    case let .favoritePrimes(.deleteFavoritePrimes(indexSet)):
        for index in indexSet {
            state.favoritePrimes.remove(at: index)
        }
    default:
        break
    }
}

func combine<Value, Action>(
    _ reducers: (inout Value, Action) -> Void...
) -> (inout Value, Action) -> Void {
    
    return { value, action in
        for reducer in reducers {
            reducer(&value, action)
        }
    }
}

func pullback<LocalValue, GlobalValue, Action>(
    _ reducer: @escaping (inout LocalValue, Action) -> Void,
    value: WritableKeyPath<GlobalValue, LocalValue>
    ) -> (inout GlobalValue, Action) -> Void {
    
    return { globalValue, action in
        reducer(&globalValue[keyPath: value], action)
    }
}



let appReducer = combine(
    pullback(counterReducer, value: \.count),
    primeModalReducer,
    pullback(favoritePrimesReducer, value: \.favoritePrimesState))

struct ContentView: View {
    var store = Store(initialValue: AppState(), reducer: appReducer)
    
    var body: some View {
        NavigationView {
            List {
                NavigationLink(
                    destination: CounterView(store: store),
                    label: {
                        Text("Counter demo")
                    })
                
                NavigationLink(
                    destination: FavouritePrimesView(store: store),
                    label: {
                        Text("Favourite primes")
                    })
            }
            .navigationTitle("State managment")
        }
    }
}

struct AlertNthPrime: Identifiable {
    var id = UUID()
    @State var value: Int
}

struct CounterView: View {
    @ObservedObject var store: Store<AppState, AppAction>
    @State var isPrimeModalShown: Bool = false
    @State var alertNthPrime: AlertNthPrime?
    
    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    store.send(.counter(.decrTapped))
                }, label: {
                    Text("-")
                })
                
                Text("\(store.value.count)")
                
                Button(action: {
                    store.send(.counter(.incrTapped))
                }, label: {
                    Text("+")
                })
            }
            
            Button(action: {
                isPrimeModalShown = true
            }, label: {
                Text("Is this prime?")
            })
            
            Button(action: {
                nthPrime(store.value.count) { prime in
                    if let prime = prime {
                        alertNthPrime = AlertNthPrime(value: prime)
                    }
                }
            }, label: {
                Text("What is the \(store.value.count) prime?")
            })
        }
        .navigationBarTitle("Counter demo")
        .sheet(isPresented: $isPrimeModalShown, onDismiss: {
            isPrimeModalShown = false
        }, content: {
            IsPrimeModalView(store: store)
        })
        .alert(item: $alertNthPrime) { (n) -> Alert in
            Alert(title: Text("The \(store.value.count) prime is \(n.value)"),
                  dismissButton: .default(Text("Ok")))
        }
    }
}

struct IsPrimeModalView: View {
    @ObservedObject var store: Store<AppState, AppAction>
    
    private func isPrime (_ p: Int) -> Bool {
        if p <= 1 { return false }
        if p <= 3 { return true }
        for i in 2...Int(sqrtf(Float(p))) {
            if p % i == 0 { return false }
        }
        return true
    }
    
    var body: some View {
        
        VStack {
            if isPrime(store.value.count) {
                Text("\(store.value.count) is prime 🎉")
                
                if store.value.favoritePrimes.contains(store.value.count) {
                    Button(action: {
                        store.send(.primeModal(.removeFavoritePrimeTapped))
                    },
                    label: {
                        Text("Remove from favorite primes")
                    })
                } else {
                    Button(action: {
                        store.send(.primeModal(.saveFavoritePrimeTapped))
                    },
                    label: {
                        Text("Save to favorite primes")
                    })
                    
                }
            } else {
                Text("\(store.value.count) is not prime :(")
            }
        }
    }
}

struct FavouritePrimesView: View {
    @ObservedObject var store: Store<AppState, AppAction>
    
    var body: some View {
        List {
            ForEach(store.value.favoritePrimes, id: \.self) { prime in
                Text("\(prime)")
            }
            .onDelete(perform: { indexSet in
                store.send(.favoritePrimes(.deleteFavoritePrimes(indexSet)))
            })
        }
        .navigationBarTitle("Favorite Primes")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDevice("iPhone 12")
    }
}
