
var coge_markers;
define( [
             'dojo/_base/declare',
             'dijit/Dialog',
            'JBrowse/View/Track/HTMLFeatures'
         ],

         function(
             declare,
             Dialog,
             HTMLFeatures
         ) {
return declare( [ HTMLFeatures ], {
    constructor: function() {
        this.inherited(arguments); // call superclass constructor
        coge_markers = this;
        this.browser = arguments[0].browser;
    },

    // ----------------------------------------------------------------

    _trackMenuOptions: function() {
        var options = this.inherited(arguments);
        var track = this;

        if (track.config.coge.type == 'notebook')
            return options;

        if (!track.config.coge.search_track)  {
            options.push({
                label: 'Find Markers in Features',
                onClick: function(){coge.create_features_overlap_search_dialog(track, 'Markers', 'markers');}
            });
        }
        options.push({
            label: 'Download Track Data',
            onClick: function(){coge.create_download_dialog(track);}
        });
        return options;
    },

    // ----------------------------------------------------------------

    updateStaticElements: function( coords ) {
        this.inherited( arguments );
        coge.adjust_nav(this.config.coge.id)
    }
});
});
