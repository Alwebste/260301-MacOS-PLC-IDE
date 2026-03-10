//! Import module — high-level import functions wrapping L5K and L5X parsers.
//!
//! These functions are the main entry points for importing Studio 5000 project files
//! into the IDE's internal PlcProject representation.

use plc_core::project::PlcProject;

/// Preview information extracted from an L5X file.
#[derive(Debug, Clone)]
pub struct ImportPreview {
    pub controller_name: String,
    pub processor_type: String,
    pub program_names: Vec<String>,
    pub routine_count: u32,
    pub tag_count: u32,
    pub rung_count: u32,
    pub warnings: Vec<String>,
}

/// Import an L5X file from its string content into a PlcProject.
pub fn import_l5x(xml_content: &str) -> Result<PlcProject, String> {
    let mut project = crate::parse_l5x(xml_content)
        .map_err(|e| format!("L5X parse error: {}", e))?;
    project.imported_from = Some("L5X".to_string());
    Ok(project)
}

/// Preview an L5X file — returns summary info for the import dialog.
pub fn preview_l5x(xml_content: &str) -> Result<ImportPreview, String> {
    let project = crate::parse_l5x(xml_content)
        .map_err(|e| format!("L5X parse error: {}", e))?;

    let mut program_names = Vec::new();
    let mut routine_count = 0u32;
    let mut rung_count = 0u32;

    for task in &project.tasks {
        for program in &task.programs {
            program_names.push(program.name.clone());
            for routine in &program.routines {
                routine_count += 1;
                rung_count += routine.rungs.len() as u32;
            }
        }
    }

    Ok(ImportPreview {
        controller_name: project.controller.name.clone(),
        processor_type: project.controller.catalog_number.clone(),
        program_names,
        routine_count,
        tag_count: project.tag_database.tags.len() as u32,
        rung_count,
        warnings: Vec::new(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_L5X: &str = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<RSLogix5000Content SchemaRevision="1.0" SoftwareRevision="34.00"
                     TargetType="Controller" ContainsContext="true">
  <Controller Name="TestCtrl" ProcessorType="1769-L33ER">
    <Tags>
      <Tag Name="Start_PB" TagType="Base" DataType="BOOL" ExternalAccess="Read/Write"/>
      <Tag Name="Motor_Run" TagType="Base" DataType="BOOL" ExternalAccess="Read/Write"/>
    </Tags>
    <Programs>
      <Program Name="MainProgram" Type="Normal">
        <Routines>
          <Routine Name="MainRoutine" Type="RLL">
            <RLLContent>
              <Rung Number="0" Type="N">
                <Comment><![CDATA[Start circuit]]></Comment>
                <Text><![CDATA[XIC(Start_PB) OTE(Motor_Run) ;]]></Text>
              </Rung>
            </RLLContent>
          </Routine>
        </Routines>
      </Program>
    </Programs>
    <Tasks>
      <Task Name="MainTask" Type="CONTINUOUS" Rate="10" Priority="10"/>
    </Tasks>
  </Controller>
</RSLogix5000Content>"#;

    #[test]
    fn import_l5x_basic() {
        let project = import_l5x(SAMPLE_L5X).unwrap();
        assert_eq!(project.name, "TestCtrl");
        assert_eq!(project.tag_database.tags.len(), 2);
        assert_eq!(project.imported_from, Some("L5X".to_string()));

        let routine = project.find_routine("MainProgram", "MainRoutine").unwrap();
        assert_eq!(routine.rungs.len(), 1);
        assert_eq!(routine.rungs[0].comment, "Start circuit");
    }

    #[test]
    fn preview_l5x_basic() {
        let preview = preview_l5x(SAMPLE_L5X).unwrap();
        assert_eq!(preview.controller_name, "TestCtrl");
        assert_eq!(preview.processor_type, "1769-L33ER");
        assert_eq!(preview.program_names, vec!["MainProgram"]);
        assert_eq!(preview.routine_count, 1);
        assert_eq!(preview.tag_count, 2);
        assert_eq!(preview.rung_count, 1);
    }

    #[test]
    fn l5x_roundtrip_export_reimport() {
        // Import → Export L5X → Re-import → compare
        let project = import_l5x(SAMPLE_L5X).unwrap();
        let exported_l5x = plc_core::export::export_l5x(&project).unwrap();
        let reimported = import_l5x(&exported_l5x).unwrap();

        assert_eq!(project.controller.name, reimported.controller.name);
        assert_eq!(project.controller.catalog_number, reimported.controller.catalog_number);

        let orig_routine = project.find_routine("MainProgram", "MainRoutine").unwrap();
        let new_routine = reimported.find_routine("MainProgram", "MainRoutine").unwrap();
        assert_eq!(orig_routine.rungs.len(), new_routine.rungs.len());
        assert_eq!(orig_routine.rungs[0].comment, new_routine.rungs[0].comment);
    }

    #[test]
    fn l5k_roundtrip_export_reimport() {
        // Import L5X → Export L5K → verify format
        let project = import_l5x(SAMPLE_L5X).unwrap();
        let l5k = plc_core::export::export_l5k(&project).unwrap();

        assert!(l5k.contains("CONTROLLER TestCtrl"));
        assert!(l5k.contains("XIC(Start_PB) OTE(Motor_Run)"));
        assert!(l5k.contains("RC:=\"Start circuit\""));
        assert!(l5k.contains("END_CONTROLLER"));
    }

    #[test]
    fn roundtrip_with_branches_and_timers() {
        let l5x = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<RSLogix5000Content SchemaRevision="1.0" SoftwareRevision="34.00"
                     TargetType="Controller" ContainsContext="true">
  <Controller Name="BranchTest" ProcessorType="1769-L33ER">
    <Tags>
      <Tag Name="A" TagType="Base" DataType="BOOL" ExternalAccess="Read/Write"/>
      <Tag Name="B" TagType="Base" DataType="BOOL" ExternalAccess="Read/Write"/>
      <Tag Name="C" TagType="Base" DataType="BOOL" ExternalAccess="Read/Write"/>
      <Tag Name="Y" TagType="Base" DataType="BOOL" ExternalAccess="Read/Write"/>
      <Tag Name="Timer1" TagType="Base" DataType="TIMER" ExternalAccess="Read/Write"/>
    </Tags>
    <Programs>
      <Program Name="MainProgram" Type="Normal">
        <Routines>
          <Routine Name="MainRoutine" Type="RLL">
            <RLLContent>
              <Rung Number="0" Type="N">
                <Comment><![CDATA[Parallel branch test]]></Comment>
                <Text><![CDATA[[XIC(A),XIC(B)] XIC(C) OTE(Y) ;]]></Text>
              </Rung>
              <Rung Number="1" Type="N">
                <Comment><![CDATA[Timer test]]></Comment>
                <Text><![CDATA[XIC(A) TON(Timer1,5000,0) ;]]></Text>
              </Rung>
            </RLLContent>
          </Routine>
        </Routines>
      </Program>
    </Programs>
    <Tasks>
      <Task Name="MainTask" Type="CONTINUOUS" Rate="10" Priority="10"/>
    </Tasks>
  </Controller>
</RSLogix5000Content>"#;

        let project = import_l5x(l5x).unwrap();
        let exported = plc_core::export::export_l5x(&project).unwrap();
        let reimported = import_l5x(&exported).unwrap();

        let orig = project.find_routine("MainProgram", "MainRoutine").unwrap();
        let new_r = reimported.find_routine("MainProgram", "MainRoutine").unwrap();
        assert_eq!(orig.rungs.len(), new_r.rungs.len());

        // Check branch structure survived
        let orig_expr = plc_core::export::format_rung_l5k(&orig.rungs[0].element);
        let new_expr = plc_core::export::format_rung_l5k(&new_r.rungs[0].element);
        assert_eq!(orig_expr, new_expr);

        // Check timer survived
        let orig_timer = plc_core::export::format_rung_l5k(&orig.rungs[1].element);
        let new_timer = plc_core::export::format_rung_l5k(&new_r.rungs[1].element);
        assert_eq!(orig_timer, new_timer);
    }
}
