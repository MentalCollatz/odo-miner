module source(source);
    parameter WIDTH = 0;
    parameter NAME = "UNUSED";
    parameter IVAL = "0";
    
    output [WIDTH-1:0] source;

    altsource_probe altsource_probe_component (
                .probe (),
                .source (source)
                // synopsys translate_off
                ,
                .clrn (),
                .ena (),
                .ir_in (),
                .ir_out (),
                .jtag_state_cdr (),
                .jtag_state_cir (),
                .jtag_state_e1dr (),
                .jtag_state_sdr (),
                .jtag_state_tlr (),
                .jtag_state_udr (),
                .jtag_state_uir (),
                .raw_tck (),
                .source_clk (),
                .source_ena (),
                .tdi (),
                .tdo (),
                .usr1 ()
                // synopsys translate_on
                );
    defparam
        altsource_probe_component.enable_metastability = "NO",
        altsource_probe_component.instance_id = NAME,
        altsource_probe_component.probe_width = 0,
        altsource_probe_component.sld_auto_instance_index = "YES",
        altsource_probe_component.sld_instance_index = 0,
        altsource_probe_component.source_initial_value = IVAL,
        altsource_probe_component.source_width = WIDTH;
endmodule

module probe(probe);
    parameter WIDTH = 0;
    parameter NAME = "UNUSED";
    
    input [WIDTH-1:0] probe;

    altsource_probe altsource_probe_component (
                .probe (probe),
                .source ()
                // synopsys translate_off
                ,
                .clrn (),
                .ena (),
                .ir_in (),
                .ir_out (),
                .jtag_state_cdr (),
                .jtag_state_cir (),
                .jtag_state_e1dr (),
                .jtag_state_sdr (),
                .jtag_state_tlr (),
                .jtag_state_udr (),
                .jtag_state_uir (),
                .raw_tck (),
                .source_clk (),
                .source_ena (),
                .tdi (),
                .tdo (),
                .usr1 ()
                // synopsys translate_on
                );
    defparam
        altsource_probe_component.enable_metastability = "NO",
        altsource_probe_component.instance_id = NAME,
        altsource_probe_component.probe_width = WIDTH,
        altsource_probe_component.sld_auto_instance_index = "YES",
        altsource_probe_component.sld_instance_index = 0,
        altsource_probe_component.source_initial_value = " 0",
        altsource_probe_component.source_width = 0;
endmodule

