onCollections ->

  class @MapViewModel
    @constructor: ->
      @showingMap = ko.observable(true)
      @sitesCount = ko.observable(0)
      @sitesCountText = ko.computed => if @sitesCount() == 1 then '1 site' else "#{@sitesCount()} sites"
      @sitesChangedListeners = []

      @reloadMapSitesAutomatically = true
      @clusters = {}
      @siteIds = {}
      @mapRequestNumber = 0
      @geocoder = new google.maps.Geocoder()

      @markerImageInactive = @markerImage 'marker_inactive.png'
      @markerImageInactiveShadow = @markerImageShadow 'marker_inactive.png'
      @markerImageTarget = @markerImage 'marker_target.png'
      @markerImageTargetShadow = @markerImageShadow 'marker_target.png'

      $.each @collections(), (idx) =>
        @collections()[idx].checked.subscribe (newValue) =>
          @reloadMapSites()

      @showingMap.subscribe =>
        @rewriteUrl()

    @initMap: ->
      return true unless @showingMap()
      return false if @map

      center = if @queryParams.lat && @queryParams.lng
                 new google.maps.LatLng(@queryParams.lat, @queryParams.lng)
               else if @currentCollection()?.position()
                 @currentCollection().position()
               else if @collections().length > 0 && @collections()[0].position()
                 @collections()[0].position()
               else
                 new google.maps.LatLng(10, 90)
      zoom = if @queryParams.z then parseInt(@queryParams.z) else 4

      mapOptions =
        center: center
        zoom: zoom
        mapTypeId: google.maps.MapTypeId.ROADMAP
        scaleControl: true
      @map = new google.maps.Map document.getElementById("map"), mapOptions

      # Create a dummy overlay to easily get a position of a marker in pixels
      # See the second answer in http://stackoverflow.com/questions/2674392/how-to-access-google-maps-api-v3-markers-div-and-its-pixel-position
      @map.dummyOverlay = new google.maps.OverlayView()
      @map.dummyOverlay.draw = ->
      @map.dummyOverlay.setMap @map

      listener = google.maps.event.addListener @map, 'bounds_changed', =>
        google.maps.event.removeListener listener
        @reloadMapSites()
        @rewriteUrl()

      google.maps.event.addListener @map, 'dragend', =>
        @reloadMapSites()
        @rewriteUrl()

      google.maps.event.addListener @map, 'zoom_changed', =>
        listener2 = google.maps.event.addListener @map, 'bounds_changed', =>
          google.maps.event.removeListener listener2
          @reloadMapSites() if @reloadMapSitesAutomatically
          @rewriteUrl()

      true

    @showMap: (callback) ->
      if @showingMap()
        if callback && typeof(callback) == 'function'
          callback()
        return

      @markers = {}
      @clusters = {}
      @showingMap(true)

      # This fixes problems when changing from fullscreen expanded to table view and then going back to map view
      @fullscreenExpanded(false) if @fullscreen()
      $('.expand-collapse_button').show()
      $(".expand-collapse_button").addClass("oleftcollapse")
      $(".expand-collapse_button").removeClass("oleftexpand")


      showMap = =>
        if $('#map').length == 0
          setTimeout(showMap, 10)
        else
          @initMap()
          if callback && typeof(callback) == 'function'
            callback()
      setTimeout(showMap, 10)
      setTimeout(window.adjustContainerSize, 10)

    @reloadMapSites: (callback) ->
      return unless @showingMap()

      bounds = @map.getBounds()

      # Wait until map is loaded
      unless bounds
        setTimeout(( => @reloadMapSites(callback)), 100)
        return

      ne = bounds.getNorthEast()
      sw = bounds.getSouthWest()
      collection_ids = if @currentCollection()
                         [@currentCollection().id]
                       else
                          c.id for c in @collections() when c.checked()
      query =
        n: ne.lat()
        s: sw.lat()
        e: ne.lng()
        w: sw.lng()
        z: @map.getZoom()
        collection_ids: collection_ids
      query.exclude_id = @selectedSite().id() if @selectedSite()?.id()
      query.search = @lastSearch() if @lastSearch()

      filter.setQueryParams(query) for filter in @filters()

      @mapRequestNumber += 1
      currentMapRequestNumber = @mapRequestNumber

      getCallback = (data = {}) =>
        return unless currentMapRequestNumber == @mapRequestNumber

        if @showingMap()
          @drawSitesInMap data.sites
          @drawClustersInMap data.clusters
          @reloadMapSitesAutomatically = true
          @adjustZIndexes()
          @updateSitesCount()
          @notifySitesChanged()

        callback() if callback && typeof(callback) == 'function'

      if query.collection_ids.length == 0
        # Save a request to the server if there are no selected collections
        getCallback()
      else
        $.get "/sites/search.json", query, getCallback

    @onSitesChanged: (listener) ->
      @sitesChangedListeners.push listener

    @notifySitesChanged: ->
      for listener in @sitesChangedListeners
        listener()

    @drawSitesInMap: (sites = []) ->
      dataSiteIds = {}
      editing = window.model.editingSiteLocation()
      selectedSiteId = @selectedSite()?.id()
      oldSelectedSiteId = @oldSelectedSite?.id() # Optimization to prevent flickering

      # Add markers if they are not already on the map
      for site in sites
        dataSiteIds[site.id] = site.id
        unless @markers[site.id]
          if site.id == oldSelectedSiteId
            @markers[site.id] = @oldSelectedSite.marker
            @deleteMarkerListeners site.id
            @setMarkerIcon @markers[site.id], 'active'
            @oldSelectedSite.deleteMarker false
            delete @oldSelectedSite
          else
            markerOptions =
              map: @map
              position: new google.maps.LatLng(site.lat, site.lng)
              zIndex: @zIndex(site.lat)
              optimized: false

            # Show site in grey if editing a site (but not if it's the one being edited)
            if editing
              markerOptions.icon = @markerImageInactive
              markerOptions.shadow = @markerImageInactiveShadow
            else if (selectedSiteId && selectedSiteId == site.id)
              markerOptions.icon = @markerImageTarget
              markerOptions.shadow = @markerImageTargetShadow

            newMarker = new google.maps.Marker markerOptions
            newMarker.name = site.name
            newMarker.site = site
            @setMarkerIcon newMarker, 'active'
            newMarker.collectionId = site.collection_id

            @markers[site.id] = newMarker
          localId = @markers[site.id].siteId = site.id
          do (localId) => @setupMarkerListeners @markers[localId], localId

      # Determine which markers need to be removed from the map
      toRemove = []
      for siteId, marker of @markers
        toRemove.push siteId unless dataSiteIds[siteId]

      # And remove them
      for siteId in toRemove
        @deleteMarker siteId

      if @oldSelectedSite
        @oldSelectedSite.deleteMarker() if @oldSelectedSite.id() != selectedSiteId
        delete @oldSelectedSite

    @setupMarkerListeners: (marker, localId) ->
      marker.clickListener = google.maps.event.addListener marker, 'click', (event) =>
        @setMarkerIcon marker, 'target'
        @editSiteFromMarker localId, marker.collectionId

      # Create a popup and position it in the top center. To do so we need to add it to the document,
      # get its width and reposition accordingly.
      marker.mouseOverListener = google.maps.event.addListener marker, 'mouseover', (event) =>
        pos = window.model.map.dummyOverlay.getProjection().fromLatLngToContainerPixel marker.getPosition()
        offset = $('#map').offset()
        marker.popup = $("<div style=\"position:absolute;top:#{offset.top + pos.y - 64}px;left:#{offset.left + pos.x}px;padding:4px;background-color:black;color:white;border:1px solid grey\">#{marker.name}</div>")
        $(document.body).append(marker.popup)
        offset = $(marker.popup).offset()
        offset.left -= $(marker.popup).width() / 2
        $(marker.popup).offset(offset)
      marker.mouseOutListener = google.maps.event.addListener marker, 'mouseout', (event) =>
        marker.popup.remove()

    @drawClustersInMap: (clusters = []) ->
      dataClusterIds = {}
      editing = window.model.editingSiteLocation()

      # Add clusters if they are not already on the map
      for cluster in clusters
        dataClusterIds[cluster.id] = cluster.id
        currentCluster = @clusters[cluster.id]
        if currentCluster
          currentCluster.setData(cluster, false)
        else
          currentCluster = @createCluster(cluster)
        currentCluster.setInactive() if editing

      # Determine which clusters need to be removed from the map
      toRemove = []
      for clusterId, cluster of @clusters
        toRemove.push clusterId unless dataClusterIds[clusterId]

      # And remove them
      @deleteCluster clusterId for clusterId in toRemove

    @setAllMarkersInactive: ->
      editingSiteId = @editingSite()?.id()?.toString()
      for siteId, marker of @markers
        @setMarkerIcon marker, (if editingSiteId == siteId then 'target' else 'inactive')
      for clusterId, cluster of @clusters
        cluster.setInactive()

    @setAllMarkersActive: ->
      selectedSiteId = @selectedSite()?.id()?.toString()
      for siteId, marker of @markers
        if selectedSiteId == siteId
          @setMarkerIcon marker, 'target'
        else
          @setMarkerIcon marker, 'active'
      for clusterId, cluster of @clusters
        cluster.setActive()

    @setMarkerIcon: (marker, icon) ->
      switch icon
        when 'active', 'null'
          marker.setIcon null
          marker.setShadow null
        when 'inactive'
          marker.setIcon @markerImageInactive
          marker.setShadow @markerImageInactiveShadow
        when 'target'
          marker.setIcon @markerImageTarget
          marker.setShadow @markerImageTargetShadow

    @deleteMarker: (siteId, removeFromMap = true) ->
      return unless @markers[siteId]
      @markers[siteId].setMap null if removeFromMap
      @deleteMarkerListeners siteId
      delete @markers[siteId]

    @deleteMarkerListeners: (siteId) ->
      for listener in ['click', 'mouseOver', 'mouseOut']
        if @markers[siteId]["#{listener}Listener"]
          google.maps.event.removeListener @markers[siteId]["#{listener}Listener"]
          delete @markers[siteId]["#{listener}Listener"]

    @createCluster: (cluster) ->
      @clusters[cluster.id] = new Cluster @map, cluster

    @deleteCluster: (id) ->
      @clusters[id].setMap null
      delete @clusters[id]

    @zIndex: (lat) ->
      bounds = @map.getBounds()
      north = bounds.getNorthEast().lat()
      south = bounds.getSouthWest().lat()
      total = north - south
      current = lat - south
      -Math.round(current * 1000000 / total)

    @adjustZIndexes: ->
      for siteId, marker of @markers
        marker.setZIndex(@zIndex(marker.getPosition().lat()))
      for clusterId, cluster of @clusters
        cluster.adjustZIndex()

    @updateSitesCount: ->
      count = 0
      bounds = @map.getBounds()
      for siteId, marker of @markers
        if bounds.contains marker.getPosition()
          count += 1
      for clusterId, cluster of @clusters
        if bounds.contains cluster.position
          count += cluster.count
      count += 1 if @selectedSite()
      @sitesCount count

    @showTable: ->
      delete @markers
      delete @clusters
      delete @map
      @selectedSite().deleteMarker() if @selectedSite()
      @exitSite() if @editingSite()
      @showingMap(false)
      @refreshTimeago()
      @makeFixedHeaderTable()
      setTimeout(window.adjustContainerSize, 10)

    @makeFixedHeaderTable: ->
      unless @showingMap()
        oldScrollLeft = $('.tablescroll').scrollLeft()

        $('table.GralTable').fixedHeaderTable 'destroy'
        $('table.GralTable').fixedHeaderTable footer: false, cloneHeadToFoot: false, themeClass: 'GralTable'

        setTimeout((->
          $('.tablescroll').scrollLeft oldScrollLeft
          window.adjustContainerSize()
        ), 20)

    @markerImage: (icon) ->
      new google.maps.MarkerImage(
        @iconUrl(icon), new google.maps.Size(20, 34), new google.maps.Point(0, 0), new google.maps.Point(10, 34)
      )

    @markerImageShadow: (icon) ->
      new google.maps.MarkerImage(
        @iconUrl(icon), new google.maps.Size(37, 34), new google.maps.Point(20, 0), new google.maps.Point(10, 34)
      )

    @iconUrl: (icon) -> icon.url ? "/assets/#{icon}"