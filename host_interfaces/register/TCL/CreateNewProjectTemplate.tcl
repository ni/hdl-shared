# githubvisible=true

set ProjName {PROJ_NAME}
create_project -force $ProjName [pwd] -part xcvu11p-flgb2104-2-e
set_property target_language VHDL [current_project]

ADD_FILES

set_property top TOP_ENTITY [current_fileset]

set_property top TOP_ENTITY [current_fileset]
set_property source_mgmt_mode All [current_project]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

exit