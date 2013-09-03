onLayers ->
  class @Hierarchy
    constructor: (initHierarchyData) ->
      @hierarchyItems = ko.observableArray $.map(initHierarchyData, (x) -> new HierarchyItem(x))

    toJSON: =>
      $.map(@hierarchyItems(), (x) -> x.toJSON())

    collapseAll: =>
      for hierarchyItem in @hierarchyItems()
        hierarchyItem.collapseAll()

