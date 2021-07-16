tool
extends ColorRect

var old_size

func _ready():
	$Height/HeightmapGenerator.material.connect("changed", self, "update_viewports")
	$AlbedoRoughness/AlbedoRoughnessLookup.material.connect("changed", self, "update_viewports")
	$SlopeData/SlopeLookup.material.connect("changed", self, "update_viewports")
	$Height/HeightmapGenerator.material.shader.connect("changed", self, "update_viewports")
	$AlbedoRoughness/AlbedoRoughnessLookup.material.shader.connect("changed", self, "update_viewports")
	$SlopeData/SlopeLookup.material.shader.connect("changed", self, "update_viewports")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	if self.rect_size != old_size:
		update_viewports()


func update_viewports():
	$Height.size = self.rect_size
	$AlbedoRoughness.size = self.rect_size
	$SlopeData.size = self.rect_size
	$Height.render_target_update_mode = Viewport.UPDATE_ONCE
	$AlbedoRoughness.render_target_update_mode = Viewport.UPDATE_ONCE
	$SlopeData.render_target_update_mode = Viewport.UPDATE_ONCE
	old_size = self.rect_size