import Foundation
import SwiftUI
import Combine

struct NavigationCoordinatableView<T: NavigationCoordinatable>: View {
    var coordinator: T
    private let id: Int
    @EnvironmentObject private var root: RootCoordinator
    private let router: NavigationRouter<T.Route>
    private let start: AnyView
    @ObservedObject var presentationHelper: PresentationHelper<T>
    
    var body: some View {
        #if os(macOS)
        commonView
            .environmentObject(router)
        #else
        if #available(iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
            commonView
                .environmentObject(router)
                .background(
                    // WORKAROUND for iOS < 14.5
                    // A bug hinders us from using modal and fullScreenCover on the same view
                    Color
                        .clear
                        .fullScreenCover(isPresented: Binding<Bool>.init(get: { () -> Bool in
                            return presentationHelper.presented?.isFullScreen == true
                        }, set: { _ in
                        
                        }), onDismiss: {
                            let presented = self.coordinator.navigationStack.value[safe: id + 1]
                            
                            switch presented?.transition {
                            case .fullScreen(let presentable):
                                if let presentable = presentable as? AnyCoordinatable {
                                    DispatchQueue.main.async {
                                        presentable.dismissalAction?()
                                        presentable.dismissalAction = nil
                                    }
                                }
                            default:
                                break
                            }
                            
                            self.coordinator.navigationStack.popTo(self.id)
                        }, content: { () -> AnyView in
                            return { () -> AnyView in
                                if let view = presentationHelper.presented?.view {
                                    return AnyView(view.environmentObject(root))
                                } else {
                                    return AnyView(EmptyView())
                                }
                            }()
                        })
                        .environmentObject(router)
                )
        } else {
            commonView
                .environmentObject(router)
        }
        #endif
    }
    
    @ViewBuilder
    var commonView: some View {
        self.start
            .background(
                NavigationLink(
                    destination: { () -> AnyView in
                        if let view = presentationHelper.presented?.view {
                            return AnyView(view.environmentObject(root))
                        } else {
                            return AnyView(EmptyView())
                        }
                    }(),
                    isActive: Binding<Bool>.init(get: { () -> Bool in
                        return presentationHelper.presented?.isPush == true
                    }, set: { _ in
                             
                    }),
                    label: {
                        EmptyView()
                    }
                )
                .hidden()
            )
            .onAppear(perform: {
                self.router.root = root.coordinator
                
                // This is here in order to sync the navigation stack array with what is actually shown on screen.
                // It's in onAppear because it seems to be the best way in SwiftUI, but it requires some hacks in order to work properly.
                // The "ready" variable is used because we want to be able to do stuff sometimes, such as setting the starting routes, without the popTo-function triggering.
                if self.presentationHelper.presented != nil && self.coordinator.navigationStack.ready == true {
                    self.coordinator.navigationStack.popTo(self.id)
                }

                DispatchQueue.main.async {
                    self.coordinator.navigationStack.ready = true
                }
            })
            .onDisappear {
                DispatchQueue.main.async {
                    self.coordinator.dismissalAction?()
                    self.coordinator.dismissalAction = nil
                }
            }
            .sheet(isPresented: Binding<Bool>.init(get: { () -> Bool in
                return presentationHelper.presented?.isModal == true
            }, set: { _ in
            
            }), onDismiss: {
                // shouldn't matter if different coordinators. also this set modal children to nil
                let presented = self.coordinator.navigationStack.value[safe: id + 1]
                
                switch presented?.transition {
                case .modal(let presentable):
                    if let presentable = presentable as? AnyCoordinatable {
                        DispatchQueue.main.async {
                            presentable.dismissalAction?()
                            presentable.dismissalAction = nil
                        }
                    }
                default:
                    break
                }
                
                self.coordinator.navigationStack.popTo(self.id)
            }, content: { () -> AnyView in
                return { () -> AnyView in
                    if let view = presentationHelper.presented?.view {
                        return AnyView(view.environmentObject(root))
                    } else {
                        return AnyView(EmptyView())
                    }
                }()
            })
    }
    
    init(id: Int, coordinator: T) {
        self.id = id
        self.coordinator = coordinator
        self.coordinator.navigationStack.resolver = self.coordinator
        
        self.presentationHelper = PresentationHelper(
            id: self.id,
            coordinator: coordinator
        )
        
        self.router = NavigationRouter(
            id: id,
            coordinator: coordinator
        )

        RouterStore.shared.store(router: router)

        if let presentation = coordinator.navigationStack.value[safe: id] {
            if let view = presentation.transition.presentable as? AnyView {
                self.start = view
            } else {
                fatalError("Can only show views")
            }
        } else if id == -1 {
            self.start = AnyView(
                coordinator
                    .start()
            )
        } else {
            fatalError()
        }
    }
}
