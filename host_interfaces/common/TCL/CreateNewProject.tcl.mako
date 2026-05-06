set ProjName {${project_name}}
create_project -force $ProjName [pwd] -part ${fpga_part}
set_property target_language VHDL [current_project]

${add_files}

${set_vhdl2008_files}

set_property top ${top_entity} [current_fileset]
set_property source_mgmt_mode All [current_project]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

exit
