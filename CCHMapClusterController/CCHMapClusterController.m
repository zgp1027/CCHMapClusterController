//
//  CCHMapClusterController.m
//  CCHMapClusterController
//
//  Copyright (C) 2013 Claus Höfele
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

// Based on https://github.com/MarcoSero/MSMapClustering by MarcoSero/WWDC 2011

#import "CCHMapClusterController.h"

#import "CCHMapClusterControllerDebugPolygon.h"
#import "CCHMapClusterControllerUtils.h"
#import "CCHMapClusterAnnotation.h"
#import "CCHMapClusterControllerDelegate.h"
#import "CCHMapViewDelegateProxy.h"
#import "CCHCenterOfMassMapClusterer.h"
#import "CCHFadeInOutMapAnimator.h"
#import "CCHMapClusterOperation.h"
#import "CCHMapTree.h"

#define NODE_CAPACITY 10
#define WORLD_MIN_LAT -85
#define WORLD_MAX_LAT 85
#define WORLD_MIN_LON -180
#define WORLD_MAX_LON 180

#define fequal(a, b) (fabs((a) - (b)) < __FLT_EPSILON__)

@interface CCHMapClusterController()<MKMapViewDelegate>

@property (nonatomic, strong) CCHMapTree *allAnnotationsMapTree;
@property (nonatomic, strong) CCHMapTree *visibleAnnotationsMapTree;
@property (nonatomic, strong) NSOperationQueue *backgroundQueue;
@property (nonatomic, strong) NSMutableArray *updateOperations;
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) CCHMapViewDelegateProxy *mapViewDelegateProxy;
@property (nonatomic, strong) id<MKAnnotation> annotationToSelect;
@property (nonatomic, strong) CCHMapClusterAnnotation *mapClusterAnnotationToSelect;
@property (nonatomic, assign) MKCoordinateSpan regionSpanBeforeChange;
@property (nonatomic, assign, getter = isRegionChanging) BOOL regionChanging;
@property (nonatomic, strong) id<CCHMapClusterer> strongClusterer;
@property (nonatomic, copy) CCHMapClusterAnnotation *(^findVisibleAnnotation)(NSSet *annotations, NSSet *visibleAnnotations);
@property (nonatomic, strong) id<CCHMapAnimator> strongAnimator;

@end

@implementation CCHMapClusterController

- (id)initWithMapView:(MKMapView *)mapView
{
    self = [super init];
    if (self) {
        _marginFactor = 0.5;
        _cellSize = 60;
        _mapView = mapView;
        _allAnnotationsMapTree = [[CCHMapTree alloc] initWithNodeCapacity:NODE_CAPACITY minLatitude:WORLD_MIN_LAT maxLatitude:WORLD_MAX_LAT minLongitude:WORLD_MIN_LON maxLongitude:WORLD_MAX_LON];
        _visibleAnnotationsMapTree = [[CCHMapTree alloc] initWithNodeCapacity:NODE_CAPACITY minLatitude:WORLD_MIN_LAT maxLatitude:WORLD_MAX_LAT minLongitude:WORLD_MIN_LON maxLongitude:WORLD_MAX_LON];
        _backgroundQueue = [[NSOperationQueue alloc] init];
        _updateOperations = [NSMutableArray array];
        
        if ([mapView.delegate isKindOfClass:CCHMapViewDelegateProxy.class]) {
            CCHMapViewDelegateProxy *delegateProxy = (CCHMapViewDelegateProxy *)mapView.delegate;
            [delegateProxy addDelegate:self];
            _mapViewDelegateProxy = delegateProxy;
        } else {
            _mapViewDelegateProxy = [[CCHMapViewDelegateProxy alloc] initWithMapView:mapView delegate:self];
        }
        
        // Keep strong reference to default instance because public property is weak
        id<CCHMapClusterer> clusterer = [[CCHCenterOfMassMapClusterer alloc] init];
        _clusterer = clusterer;
        _strongClusterer = clusterer;
        id<CCHMapAnimator> animator = [[CCHFadeInOutMapAnimator alloc] init];
        _animator = animator;
        _strongAnimator = animator;
        
        [self setReuseExistingClusterAnnotations:YES];
    }
    
    return self;
}

- (NSSet *)annotations
{
    return [self.allAnnotationsMapTree.annotations copy];
}

- (void)setClusterer:(id<CCHMapClusterer>)clusterer
{
    _clusterer = clusterer;
    self.strongClusterer = nil;
}

- (void)setAnimator:(id<CCHMapAnimator>)animator
{
    _animator = animator;
    self.strongAnimator = nil;
}

- (void)setReuseExistingClusterAnnotations:(BOOL)reuseExistingClusterAnnotations
{
    _reuseExistingClusterAnnotations = reuseExistingClusterAnnotations;
    if (reuseExistingClusterAnnotations) {
        self.findVisibleAnnotation = ^CCHMapClusterAnnotation *(NSSet *annotations, NSSet *visibleAnnotations) {
            return CCHMapClusterControllerFindVisibleAnnotation(annotations, visibleAnnotations);
        };
    } else {
        self.findVisibleAnnotation = ^CCHMapClusterAnnotation *(NSSet *annotations, NSSet *visibleAnnotations) {
            return nil;
        };
    }
}

- (void)sync
{
    for (NSOperation *operation in self.updateOperations) {
        [operation cancel];
    }
    [self.updateOperations removeAllObjects];
    [self.backgroundQueue waitUntilAllOperationsAreFinished];
}

- (void)addAnnotations:(NSArray *)annotations withCompletionHandler:(void (^)())completionHandler
{
    [self sync];
    
    [self.backgroundQueue addOperationWithBlock:^{
        BOOL updated = [self.allAnnotationsMapTree addAnnotations:annotations];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (updated && !self.isRegionChanging) {
                [self updateAnnotationsWithCompletionHandler:completionHandler];
            } else if (completionHandler) {
                completionHandler();
            }
        });
    }];
}

- (void)removeAnnotations:(NSArray *)annotations withCompletionHandler:(void (^)())completionHandler
{
    [self sync];
    
    [self.backgroundQueue addOperationWithBlock:^{
        BOOL updated = [self.allAnnotationsMapTree removeAnnotations:annotations];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (updated && !self.isRegionChanging) {
                [self updateAnnotationsWithCompletionHandler:completionHandler];
            } else if (completionHandler) {
                completionHandler();
            }
        });
    }];
}

- (void)updateAnnotationsWithCompletionHandler:(void (^)())completionHandler
{
    [self sync];
    
    CCHMapClusterOperation *operation = [[CCHMapClusterOperation alloc] initWithMapView:self.mapView cellSize:self.cellSize marginFactor:self.marginFactor];
    operation.findVisibleAnnotation = self.findVisibleAnnotation;
    operation.completionHandler = completionHandler;
    operation.allAnnotationsMapTree = self.allAnnotationsMapTree;
    operation.visibleAnnotationsMapTree = self.visibleAnnotationsMapTree;
    operation.clusterer = self.clusterer;
    operation.animator = self.animator;
    operation.delegate = self.delegate;
    operation.clusterController = self;
    
    __weak NSOperation *weakOperation = operation;
    operation.completionBlock = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.updateOperations removeObject:weakOperation]; // also prevents retain cycle
        });
    };
    [self.updateOperations addObject:operation];
    [self.backgroundQueue addOperation:operation];

    // Debugging
    if (self.isDebuggingEnabled) {
        double cellMapSize = [CCHMapClusterOperation cellMapSizeForCellSize:self.cellSize withMapView:self.mapView];
        MKMapRect gridMapRect = [CCHMapClusterOperation gridMapRectForMapRect:self.mapView.visibleMapRect withCellMapSize:cellMapSize marginFactor:self.marginFactor];
        [self updateDebugPolygonsInGridMapRect:gridMapRect withCellMapSize:cellMapSize];
    }
}

- (void)updateDebugPolygonsInGridMapRect:(MKMapRect)gridMapRect withCellMapSize:(double)cellMapSize
{
    MKMapView *mapView = self.mapView;
    
    // Remove old polygons
    for (id<MKOverlay> overlay in mapView.overlays) {
        if ([overlay isKindOfClass:CCHMapClusterControllerDebugPolygon.class]) {
            CCHMapClusterControllerDebugPolygon *debugPolygon = (CCHMapClusterControllerDebugPolygon *)overlay;
            if (debugPolygon.mapClusterController == self) {
                [mapView removeOverlay:overlay];
            }
        }
    }
    
    // Add polygons outlining each cell
    CCHMapClusterControllerEnumerateCells(gridMapRect, cellMapSize, ^(MKMapRect cellMapRect) {
        cellMapRect.origin.x -= MKMapSizeWorld.width;  // fixes issue when view port spans 180th meridian
        
        MKMapPoint points[4];
        points[0] = MKMapPointMake(MKMapRectGetMinX(cellMapRect), MKMapRectGetMinY(cellMapRect));
        points[1] = MKMapPointMake(MKMapRectGetMaxX(cellMapRect), MKMapRectGetMinY(cellMapRect));
        points[2] = MKMapPointMake(MKMapRectGetMaxX(cellMapRect), MKMapRectGetMaxY(cellMapRect));
        points[3] = MKMapPointMake(MKMapRectGetMinX(cellMapRect), MKMapRectGetMaxY(cellMapRect));
        CCHMapClusterControllerDebugPolygon *debugPolygon = (CCHMapClusterControllerDebugPolygon *)[CCHMapClusterControllerDebugPolygon polygonWithPoints:points count:4];
        debugPolygon.mapClusterController = self;
        [mapView addOverlay:debugPolygon];
    });
}

- (void)deselectAllAnnotations
{
    NSArray *selectedAnnotations = self.mapView.selectedAnnotations;
    for (id<MKAnnotation> selectedAnnotation in selectedAnnotations) {
        [self.mapView deselectAnnotation:selectedAnnotation animated:YES];
    }
}

- (void)selectAnnotation:(id<MKAnnotation>)annotation andZoomToRegionWithLatitudinalMeters:(CLLocationDistance)latitudinalMeters longitudinalMeters:(CLLocationDistance)longitudinalMeters
{
    // Check for valid annotation
    BOOL existingAnnotation = [self.annotations containsObject:annotation];
    NSAssert(existingAnnotation, @"Invalid annotation - can only select annotations previously added by calling addAnnotations:withCompletionHandler:");
    if (!existingAnnotation) {
        return;
    }
    
    // Deselect annotations
    [self deselectAllAnnotations];
    
    // Zoom to annotation
    self.annotationToSelect = annotation;
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(annotation.coordinate, latitudinalMeters, longitudinalMeters);
    [self.mapView setRegion:region animated:YES];
    if (CCHMapClusterControllerCoordinateEqualToCoordinate(region.center, self.mapView.centerCoordinate)) {
        // Manually call update methods because region won't change
        [self mapView:self.mapView regionWillChangeAnimated:YES];
        [self mapView:self.mapView regionDidChangeAnimated:YES];
    }
}

#pragma mark - Map view proxied delegate methods

- (void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray *)annotationViews
{
    // Animate annotations that get added
    [self.animator mapClusterController:self didAddAnnotationViews:annotationViews];
}

- (void)mapView:(MKMapView *)mapView regionWillChangeAnimated:(BOOL)animated
{
    self.regionSpanBeforeChange = mapView.region.span;
    self.regionChanging = YES;
}

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated
{
    self.regionChanging = NO;
    
    // Deselect all annotations when zooming in/out. Longitude delta will not change
    // unless zoom changes (in contrast to latitude delta).
    BOOL hasZoomed = !fequal(mapView.region.span.longitudeDelta, self.regionSpanBeforeChange.longitudeDelta);
    if (hasZoomed) {
        [self deselectAllAnnotations];
    }
    
    // Update annotations
    [self updateAnnotationsWithCompletionHandler:^{
        if (self.annotationToSelect) {
            // Map has zoomed to selected annotation; search for cluster annotation that contains this annotation
            CCHMapClusterAnnotation *mapClusterAnnotation = CCHMapClusterControllerClusterAnnotationForAnnotation(self.mapView, self.annotationToSelect, mapView.visibleMapRect);
            self.annotationToSelect = nil;
            
            if (CCHMapClusterControllerCoordinateEqualToCoordinate(self.mapView.centerCoordinate, mapClusterAnnotation.coordinate)) {
                // Select immediately since region won't change
                [self.mapView selectAnnotation:mapClusterAnnotation animated:YES];
            } else {
                // Actual selection happens in next call to mapView:regionDidChangeAnimated:
                self.mapClusterAnnotationToSelect = mapClusterAnnotation;
                
                // Dispatch async to avoid calling regionDidChangeAnimated immediately
                dispatch_async(dispatch_get_main_queue(), ^{
                    // No zooming, only panning. Otherwise, annotation might change to a different cluster annotation
                    [self.mapView setCenterCoordinate:mapClusterAnnotation.coordinate animated:NO];
                });
            }
        } else if (self.mapClusterAnnotationToSelect) {
            // Map has zoomed to annotation
            [self.mapView selectAnnotation:self.mapClusterAnnotationToSelect animated:YES];
            self.mapClusterAnnotationToSelect = nil;
        }
    }];
}

@end
