--Ciro, nossos problemas estão na seção da linha 374. A gente cria uma peça do tetris, e ela cai, mas nao conseguimos
--apagar o rastro dela, alem disso aparecem pixels em lugares que não teriam que estar aparecendo.

library ieee;
use ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.all;

entity game_board IS
    port(
        SW                      : in std_logic_vector(0 downto 0);
        CLOCK_50                : in std_logic;
        KEY				        : in std_logic_vector(0 downto 0);
        LEDR                    : out std_logic_vector (9 downto 0);
        VGA_R, VGA_G, VGA_B	    : out std_logic_vector(7 DOWNTO 0);
        VGA_HS, VGA_VS		    : out std_logic;
        VGA_BLANK_N, VGA_SYNC_N : out std_logic;
        VGA_CLK                 : out std_logic;
        PS2_DAT 	            : inout	STD_LOGIC;	--	PS2 Data
		PS2_CLK		            : inout	STD_LOGIC		--	PS2 Clock
    );
end entity;

architecture behavior OF game_board IS
    component vgacon IS
        generic (
            NUM_HORZ_PIXELS : NATURAL := 128;	-- Number of horizontal pixels
            NUM_VERT_PIXELS : NATURAL := 96		-- Number of vertical pixels
        );
        port (
            clk50M, rstn              : in std_logic;
            write_clk, write_enable   : in std_logic;
            write_addr                : in INTEGER range 0 TO NUM_HORZ_PIXELS * NUM_VERT_PIXELS - 1;
            data_in                   : in std_logic_vector (2 DOWNTO 0);
            vga_clk                   : buffer std_logic;
            red, green, blue          : out std_logic_vector (7 DOWNTO 0);
            hsync, vsync              : out std_logic;
            sync, blank               : out std_logic
        );
    end component;

    component kbdex_ctrl is
        generic(
            clkfreq : integer);
        port(
            ps2_data	:	inout	std_logic;
            ps2_clk		:	inout	std_logic;
            clk			:	in 	std_logic;
            en			:	in 	std_logic;
            resetn		:	in 	std_logic;
            lights		:   in	std_logic_vector(2 downto 0); -- lights(Caps, Nun, Scroll)
            key_on		:	out	std_logic_vector(2 downto 0);
            key_code	:	out	std_logic_vector(47 downto 0)
        );
    end component;

    component clock_div is
        port (
            clock       : in std_logic;
            clock_hz    : out std_logic;
            clock_half  : out std_logic
        );
    end component;

    component mov_piece is
    port (
        clock		: in 	std_logic;
        key_on 		: in 	std_logic_vector(2 downto 0);
        key_code 	: in 	std_logic_vector(47 downto 0);
        direction	: out 	std_logic_vector(1 downto 0);
        mov 		: out 	std_logic;
        rotation	: out 	std_logic);
    end component;

    component create_piece is
        port (
            clock         : in  std_logic;
            sync_reset    : in  std_logic;
            en            : in  std_logic;
            piece         : out std_logic_vector(2 downto 0));
    end component;



    constant HORZ_SIZE : integer := 50;
    constant VERT_SIZE : integer := 22;
    constant X_INITIAL : integer := 24;
    constant Y_INITIAL : integer := 2;
    signal slow_clock : std_logic;
    signal not_so_slow_clock : std_logic;
    signal clear_video_address	,
    normal_video_address	,
    video_address			: integer range 0 to HORZ_SIZE * VERT_SIZE- 1;

    --definicao da peca atual, matriz 4x2 que guarda as coordenadas de cada quadrado
    type pieces_type is array (0 to 3, 0 to 1) of integer range 0 to HORZ_SIZE;
    signal piece : pieces_type;

    --definicao da matriz que contem a cor de cada "pixel"
    -- o vetor eh definido em ordem crescente como o video_adress
    TYPE color_matrix is array (0 to 263) of std_logic_vector(2 downto 0);
    signal pos_color: color_matrix;

    -- Interface com o create_piece
    signal new_piece_flag : std_logic;
    signal new_piece_type, current_piece_type : std_logic_vector(2 downto 0);
    -- Interface com a memória de vídeo do controlador

    signal we : std_logic;                        -- write enable ('1' p/ escrita)
    signal addr : integer range 0 to 12287;       -- endereco mem. vga
    signal pixel : std_logic_vector(2 downto 0);  -- valor de cor do pixel
    signal pixel_bit : std_logic;                 -- um bit do vetor acima

    -- Sinais dos contadores de linhas e colunas utilizados para percorrer
    -- as posições da memória de vídeo (pixels) no momento de construir um quadro.

    signal linha : integer range 0 to VERT_SIZE-1;  -- linha atual
    signal col : integer range 0 to HORZ_SIZE-1;  -- coluna atual

    signal col_rstn : std_logic;          -- reset do contador de colunas
    signal col_enable : std_logic;        -- enable do contador de colunas

    signal line_rstn : std_logic;          -- reset do contador de linhas
    signal line_enable : std_logic;        -- enable do contador de linhas

    signal fim_escrita : std_logic;       -- '1' quando um quadro terminou de ser
                                        -- escrito na memória de vídeo
    --
    signal piece_x : integer range 0 to HORZ_SIZE-1;  -- coluna atual da peca
    signal piece_y : integer range 0 to VERT_SIZE-1;   -- linha atual da peca

    signal atualiza_piece_x : std_logic;    -- se '1' = peca muda sua pos. no eixo x
    signal atualiza_piece_y : std_logic;    -- se '1' = peca muda sua pos. no eixo y

    signal START_GAME            : std_logic;
    signal clash, clash_l        : std_logic;

    signal lights, key_on		: std_logic_vector(2 downto 0);
    signal key_code             : std_logic_vector(47 downto 0);
    signal try_collision        :std_logic;
    --acho que aqui um dos estados que pode ser definido eh o menu...
    TYPE VGA_STATES IS (NEW_GAME, INICIO, MOVE, NEW_PIECE, COLLISION, DRAW, MENU, OVER);
    signal state: VGA_STATES;
    signal fall : std_logic;
    signal clash_new : std_logic;
    signal after_move : std_logic;

    signal switch, rstn , sync, blank : std_logic;
    signal clock_count : std_logic;
    signal mov, rotation : std_logic;                       -- 1 quando peca esta se movendo ou rotacionando
    signal direction     : std_logic_vector(1 downto 0);    -- vetor que indica a direcao da peca
    signal current_color: std_logic_vector(2 downto 0);     -- cor atual da peca
    signal aux_led :std_logic_vector (9 downto 1);
    signal collision2 : std_logic := '0';
    BEGIN

    --variaveis para testes
    rstn <= KEY(0);

    --evita a cor branca
    current_color <= "010" when current_piece_type = "111" else current_piece_type;

    vga_component: vgacon generic map (
        NUM_HORZ_PIXELS => HORZ_SIZE,
        NUM_VERT_PIXELS => VERT_SIZE
    ) port map (
        clk50M          => CLOCK_50,
        rstn            => rstn,
        write_clk		=> CLOCK_50,
        write_enable	=> we,
        write_addr      => video_address,
        vga_clk         => VGA_CLK,
        data_in         => pixel,
        red				=> VGA_R,
        green			=> VGA_G,
        blue			=> VGA_B,
        hsync			=> VGA_HS,
        vsync			=> VGA_VS,
        sync			=> sync,
        blank			=> blank);

        VGA_SYNC_N <= NOT sync;
        VGA_BLANK_N <= NOT blank;

    clock_component: clock_div port map (
        clock       => CLOCK_50,
        clock_hz    => slow_clock,
        clock_half  => not_so_slow_clock);

    kbd_ctrl : kbdex_ctrl generic map (50000)
    port map(
		ps2_data    => PS2_DAT,
        ps2_clk		=> PS2_CLK,
        clk			=> CLOCK_50,
        en			=> '1', -- ativo alto
        resetn		=> '1', --ativo baixo
        lights		=> "000",
        key_on		=> key_on,
        key_code	=> key_code);

    movement: mov_piece port map (
        clock		=> CLOCK_50,
        key_on 		=> key_on,
        key_code 	=> key_code,
        direction	=> direction,
        mov 		=> mov,
        rotation    => rotation);

    create_piece_prt:   create_piece port map (
        clock       => CLOCK_50,
        sync_reset  => START_GAME,
        en          => '1',
        piece       => new_piece_type);



    -- precisamos de funcoes para atualizar cada um dos dois signals
    -- video_address <= normal_video_address when state = NORMAL else clear_video_address;

    --precisamos dos processos de conta_coluna e conta_linha para
    -- mandar todas as posicoes da tela ao vgacon.
    conta_coluna: process (CLOCK_50, col_rstn)
    begin  -- process conta_coluna
        if col_rstn = '0' then                  -- asynchronous reset (active low)
            col <= 19;
        elsif CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
            if col_enable = '1' then
                    if col = 30 then               -- conta de 0 ate HORZ_SIZE-1
                        col <= 19;
                    else
                        col <= col + 1;
                    end if;
                end if;
            end if;
    end process;

    conta_linha: process (CLOCK_50, line_rstn)
    begin  -- process conta_linha
        if line_rstn = '0' then                  -- asynchronous reset (active low)
            linha <= 0;
        elsif CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
        -- o contador de linha só incrementa quando o contador de colunas
        -- chegou ao fim
            if line_enable = '1' and col = 30 then
                if col = 30 then
                    if linha = VERT_SIZE - 1 then               -- conta de 0 a 95 (96 linhas)
                        linha <= 0;
                    else
                        linha <= linha + 1;
                    end if;
                end if;
            end if;
        end if;
    end process conta_linha;




    -- manda o endereco atual e a cor desse endereco para o vgacon.
    video_address  <= col + (HORZ_SIZE * linha);
    pixel          <= pos_color((col - 19) + (12*linha));

    fim_escrita <= '1' when (linha = VERT_SIZE - 1) and (col = 30)
                   else '0';

    game_logic: process(CLOCK_50)
    begin
        if CLOCK_50'event and CLOCK_50 = '1' then
            --desenha a borda e limpa a tela
            if START_GAME = '1' then
                for lin_y in 0 to 21 loop
                    for col_x in 19 to 30 loop
                        if(lin_y = 0 or lin_y = 21) then
                            pos_color((col_x -19)+(lin_y*12)) <= "111";
                        elsif(col_x=19 or col_x = 30) then
                            pos_color((col_x -19)+(lin_y*12)) <= "111";
                        else
                            pos_color((col_x -19)+(lin_y*12)) <= "000";
                        end if;
                    end loop;
                end loop;
                    piece(0,0) <= X_INITIAL;
                    piece(0,1) <= Y_INITIAL;
                    piece(1,0) <= X_INITIAL;
                    piece(1,1) <= Y_INITIAL+1;
                    piece(2,0) <= X_INITIAL;
                    piece(2,1) <= Y_INITIAL+2;
                    piece(3,0) <= X_INITIAL+1;
                    piece(3,1) <= Y_INITIAL+2;
    --            --cria nova peca
        elsif new_piece_flag = '1' and not_so_slow_clock = '1' then
                current_piece_type <= new_piece_type;
--                clash <= '0';
--                clash_new <= '0';
                if current_piece_type = "001" then --tipo L
                    piece(0,0) <= X_INITIAL;
                    piece(0,1) <= Y_INITIAL;
                    piece(1,0) <= X_INITIAL;
                    piece(1,1) <= Y_INITIAL+1;
                    piece(2,0) <= X_INITIAL;
                    piece(2,1) <= Y_INITIAL+2;
                    piece(3,0) <= X_INITIAL+1;
                    piece(3,1) <= Y_INITIAL+2;
                elsif current_piece_type = "010" then --tipo J
                    piece(0,0) <= X_INITIAL;
                    piece(0,1) <= Y_INITIAL;
                    piece(1,0) <= X_INITIAL;
                    piece(1,1) <= Y_INITIAL+1;
                    piece(2,0) <= X_INITIAL;
                    piece(2,1) <= Y_INITIAL+2;
                    piece(3,0) <= X_INITIAL-1;
                    piece(3,1) <= Y_INITIAL+2;
                elsif current_piece_type = "011" then --tipo T
                    piece(0,0) <= X_INITIAL;
                    piece(0,1) <= Y_INITIAL;
                    piece(1,0) <= X_INITIAL;
                    piece(1,1) <= Y_INITIAL+1;
                    piece(2,0) <= X_INITIAL+1;
                    piece(2,1) <= Y_INITIAL+1;
                    piece(3,0) <= X_INITIAL-1;
                    piece(3,1) <= Y_INITIAL+1;
                elsif current_piece_type = "100" then --tipo quadrado
                    piece(0,0) <= X_INITIAL;
                    piece(0,1) <= Y_INITIAL;
                    piece(1,0) <= X_INITIAL+1;
                    piece(1,1) <= Y_INITIAL;
                    piece(2,0) <= X_INITIAL;
                    piece(2,1) <= Y_INITIAL+1;
                    piece(3,0) <= X_INITIAL+1;
                    piece(3,1) <= Y_INITIAL+1;
                elsif current_piece_type = "101" then --tipo reto
                    piece(0,0) <= X_INITIAL;
                    piece(0,1) <= Y_INITIAL;
                    piece(1,0) <= X_INITIAL;
                    piece(1,1) <= Y_INITIAL+1;
                    piece(2,0) <= X_INITIAL;
                    piece(2,1) <= Y_INITIAL+2;
                    piece(3,0) <= X_INITIAL;
                    piece(3,1) <= Y_INITIAL+3;
                elsif current_piece_type = "110" then --tipo cao esq
                    piece(0,0) <= X_INITIAL;
                    piece(0,1) <= Y_INITIAL;
                    piece(1,0) <= X_INITIAL-1;
                    piece(1,1) <= Y_INITIAL;
                    piece(2,0) <= X_INITIAL;
                    piece(2,1) <= Y_INITIAL+1;
                    piece(3,0) <= X_INITIAL+1;
                    piece(3,1) <= Y_INITIAL+1;
                elsif current_piece_type = "111" then --tipo cao direita
                    piece(0,0) <= X_INITIAL;
                    piece(0,1) <= Y_INITIAL;
                    piece(1,0) <= X_INITIAL+1;
                    piece(1,1) <= Y_INITIAL;
                    piece(2,0) <= X_INITIAL;
                    piece(2,1) <= Y_INITIAL+1;
                    piece(3,0) <= X_INITIAL-1;
                    piece(3,1) <= Y_INITIAL+1;
                end if;

--                --testa se a nova peca vai colidir
--                for i in 0 to 3 loop
--                    if pos_color(piece(i, 0) + piece(i, 1) * HORZ_SIZE ) /= "000" then
--                        clash_new <= '1';
--                        clash <= '1';
--                    end if;
--                end loop;
--
--
--           -- logica do movimento da peca
--            --apaga a posicao atual e escreve na prox
--            elsif mov = '1' then
--                clash <= '0';
--                clash_l <= '0';
--                clash_new <= '0';
--                if direction = "10" then -- baixo
--                    for i in 0 to 3 loop
--                        pos_color(piece(i, 0) + (piece(i, 1) * HORZ_SIZE )) <= "000";
--                    end loop;
--                    for i in 0 to 3 loop
--                        if pos_color(piece(i, 0) + ((piece(i, 1) + 1) * HORZ_SIZE )) /= "000" then
--                            clash <= '1';
--                        end if;
--                    end loop;
--                    if clash = '1' then
--                        for i in 0 to 3 loop
--                            pos_color(piece(i, 0) + (piece(i, 1) * HORZ_SIZE )) <= current_color;
--                        end loop;
--                    else
--                        for i in 0 to 3 loop
--                            piece(i, 1) <= piece(i, 1) + 1;
--                            pos_color(piece(i, 0) + ((piece(i, 1)+1) * HORZ_SIZE )) <= current_color;
--                        end loop;
--                    end if;
--                elsif direction = "11" then -- esquerda
--                    for i in 0 to 3 loop
--                        pos_color(piece(i, 0) + (piece(i, 1) * HORZ_SIZE )) <= "000"; --apaga peca atual
--                    end loop;
--                    for i in 0 to 3 loop
--                        if pos_color(piece(i, 0) - 1 + piece(i, 1) * HORZ_SIZE) /= "000" then --ve se a posicao a esq eh dif de preto
--                            clash_l <= '1'; -- clash lateral
--                        end if;
--                    end loop;
--                    if clash_l = '1' then
--                        for i in 0 to 3 loop
--                            pos_color(piece(i, 0) + (piece(i, 1) * HORZ_SIZE )) <= current_color;
--                        end loop;
--                    else
--                        for i in 0 to 3 loop
--                            piece(i, 0) <= piece(i, 0) - 1;
--                            pos_color(piece(i, 0) - 1 + (piece(i, 1) * HORZ_SIZE )) <= current_color;
--                        end loop;
--                    end if;
--                elsif direction = "01" then -- direita
--                    for i in 0 to 3 loop
--                        pos_color(piece(i, 0) + (piece(i, 1) * HORZ_SIZE )) <= "000";
--                    end loop;
--                    for i in 0 to 3 loop
--                        if pos_color(piece(i, 0) + 1 + piece(i, 1) * HORZ_SIZE) /= "000" then
--                            clash_l <= '1';
--                        end if;
--                    end loop;
--                    if clash_l = '1' then
--                        for i in 0 to 3 loop
--                            pos_color(piece(i, 0) + (piece(i, 1) * HORZ_SIZE )) <= current_color;
--                        end loop;
--                    else
--                        for i in 0 to 3 loop
--                            piece(i, 0) <= piece(i, 0) + 1;
--                            pos_color(piece(i, 0) + 1 + (piece(i, 1) * HORZ_SIZE )) <= current_color;
--                        end loop;
--                    end if;
--                end if;
--            -- queda da peca natural

            elsif fall = '1' and slow_clock = '1' then
                if collision2 = '0' then
                    for i in 0 to 3 loop
                        pos_color(piece(i, 0) - 19 +( piece(i, 1) * 12)) <= "000"; --supostamente apaga a peca
                    end loop;
                end if;
--            elsif try_collision = '1' and slow_clock ='1' then
--                clash <= '0';
--                for i in 0 to 3 loop
--                    if pos_color(piece(i, 0) - 19 + ((piece(i, 1) + 1) * 12 )) /= "000" then
--                        clash <= '1';
--                    end if;
--                end loop;
            elsif after_move = '1' and slow_clock = '1' then
--                if clash = '1' then
--                    for i in 0 to 3 loop
--                        pos_color(piece(i, 0) - 19 + ( piece(i, 1) * 12)) <= current_color; --supostamente apaga a peca
--                    end loop;
--                else 
                    --colLISION2 <= '0';
                    for i in 0 to 3 loop
                        piece(i,1) <= piece (i,1) + 1;
                        pos_color(piece(i, 0) - 19 + (piece(i, 1) + 1)* 12) <= current_color; --supostamente apaga a peca
                    end loop;
--                end if;
            end if;
                 clash <= '0';
                for i in 0 to 3 loop
                    if pos_color(piece(i, 0) - 19 + ((piece(i, 1) + 1) * 12 )) /= "000" then
                        clash <= '1';
                    end if;
                end loop;
                if state = IniCIO and clash = '1' then
                    colLISION2 <= '1';
                end if;
                
 
    end if;
    end process;

    logica_mealy: process (clock_50)
    begin  -- process logica_mealy
        if CLOCK_50'event and CLOCK_50 = '1' then
            case state is
                when NEW_GAME  =>

                    START_GAME     <= '1'; -- Desenha e limpa o tabuleiro
                    new_piece_flag <= '0';
                    after_move     <= '0';
                    try_collision  <= '0';
                    fall           <= '0';
                    we             <= '0';
                    line_rstn      <= '1';  -- reset é active low!
                    line_enable    <= '0';
                    col_rstn       <= '1';  -- reset é active low!
                    col_enable     <= '0';
                    aux_led <= "100000000"; -- Usado pra debug

                when NEW_PIECE =>
                    try_collision  <= '0';
                    after_move     <= '0';
                    START_GAME     <= '0';
                    new_piece_flag <= '1';  -- Permite a criacao da peca
                    fall           <= '0';  -- 1 para peca cair a 1 celula por s
                    we             <= '0';
                    line_rstn      <= '1';
                    line_enable    <= '0';
                    col_rstn       <= '1';
                    col_enable     <= '0';
                    aux_led <= "010000000"; -- Usado pra debug

                -- Prepara a tela pra ser escrita, resetando linha e coluna
                when INICIO =>
                    try_collision  <= '0';
                    after_move     <= '1';
                    START_GAME     <= '0';
                    new_piece_flag <= '0';
                    fall           <= '0';
                    we             <= '0';
                    line_rstn      <= '0';
                    line_enable    <= '0';
                    col_rstn       <= '0';
                    col_enable     <= '0';
                    aux_led <= "000100000"; -- Usado pra debug

                -- Passa matriz de cores para a tela - unico estado com we
                
                when COLLISION =>
                    try_collision  <= '1';
                    START_GAME     <= '0';
                    new_piece_flag <= '0';
                    after_move     <= '0';
                    fall           <= '0';
                    we             <= '0';
                    line_rstn      <= '1';
                    line_enable    <= '0';
                    col_rstn       <= '1';
                    col_enable     <= '0';
                    aux_led <= "000010000"; -- Usado pra debug

                when DRAW =>
                    try_collision  <= '0';
                    START_GAME     <= '0';
                    new_piece_flag <= '0';
                    after_move     <= '0';
                    fall           <= '0';
                    we             <= '1';
                    line_rstn      <= '1';
                    line_enable    <= '1';
                    col_rstn       <= '1';
                    col_enable     <= '1';
                    aux_led <= "000010000"; -- Usado pra debug

                when MOVE =>
                
                    try_collision  <= '0';
                    START_GAME     <= '0';
                    new_piece_flag <= '0';
                    after_move     <= '0';
                    fall           <= '1';
                    we             <= '0';
                    line_rstn      <= '1';
                    line_enable    <= '0';
                    col_rstn       <= '1';
                    col_enable     <= '0';
                    aux_led <= "000001000"; -- Usado pra debug

                -- nao implementado
                when OVER =>
                    try_collision  <= '0';
                    new_piece_flag <= '0';
                    START_GAME     <= '0';
                    fall           <= '0';
                    we             <= '0';
                    after_move     <= '0';
                    line_rstn      <= '1';
                    line_enable    <= '0';
                    col_rstn       <= '1';
                    col_enable     <= '0';
                    aux_led <= "000000010"; -- Usado pra debug

                when others =>
                    try_collision  <= '0';
                    START_GAME     <= '0';
                    fall           <= '0';
                    after_move     <= '0';
                    we             <= '0';
                    line_rstn      <= '1';
                    line_enable    <= '0';
                    col_rstn       <= '1';
                    col_enable     <= '0';
                    aux_led <= "000000000"; -- Usado pra debug
            end case;
        LEDR <= aux_led & clash;
       end if;

   end process logica_mealy;

    seq_fsm: process (CLOCK_50, rstn)
    begin  -- process seq_fsm
        if rstn = '0' then                  -- asynchronous reset (active low)
            state <= NEW_GAME;
        elsif  CLOCK_50'event and CLOCK_50 = '1' then
        case state is
            when NEW_GAME => STATE <= NEW_PIECE;
            
            when NEW_PIECE =>
                if not_so_slow_clock = '1' then
                    STATE <= INICIO; 
                else
                   STATE <= NEW_PIECE;
                end if;
            -- Prepara a tela pra ser escrita, resetando linha e coluna

            when INICIO =>
                if clash = '1' then
                    if clash_new = '1' then
                        STATE <= OVER;
                    else
                        STATE <= NEW_PIECE;
                    end if;
                elsif not_so_slow_clock = '1' then
                    STATE <= DRAW;
                    else
                    STATE <= INICIO;
                    end if;


            -- Passa matriz de cores para a tela - unico estado com we
            when DRAW =>
                if fim_escrita = '1' then
                    STATE <= MOVE;
                else
                    STATE <= DRAW;
                end if;


            when MOVE =>
                if slow_clock = '1' then
                    STATE <= COLLISION;
                else
                    STATE <= MOVE;
                end if;
                
            when COLLISION =>
                state <= INICIO;

            -- nao implementado
            when OVER => STATE <= NEW_GAME;

            when others => STATE     <= NEW_GAME;

    end case;

        end if;
    end process seq_fsm;

END ARCHITECTURE;
