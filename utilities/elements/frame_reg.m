function [m, acorrf, acorr, scl] = frame_reg(m, imaxn, Fs, pixs, scl, sigma_x, sigma_f, sigma_d)
% register movies with the hierarchical movement correction
%   Jinghao Lu, 09/01/2017

    hreg = tic;
    %% initialization %%
    %%% initialize parameters %%%
    [pixh, pixw, nf] = size(m, 'reg');
    if nargin < 4 || isempty(Fs)
        defpar = default_parameters;
        Fs = defpar.Fsi_new;
    end
    
    if nargin < 5 || isempty(pixs)
        pixs = min(pixh, pixw);
    end
    
    if nargin < 6 || isempty(scl)
        defpar = default_parameters;
        scl = defpar.mc_scl;
    end
    
    if nargin < 7 || isempty(sigma_x)
        defpar = default_parameters;
        sigma_x = defpar.mc_sigma_x;
    end
    
    if nargin < 8 || isempty(sigma_f)
        defpar = default_parameters;
        sigma_f = defpar.mc_sigma_f;
    end
    
    if nargin < 9 || isempty(sigma_d)
        defpar = default_parameters;
        sigma_d = defpar.mc_sigma_d;
    end

    %%% prepare parallel computing %%%
    if isempty(gcp('nocreate'))
        parpool(feature('numCores'));
    end
    
    %%% select gpu %%%
    select_gpu;
        
    %%% preprocess Y first %%%
    dthres = 0.1;
    mskpre = dominant_patch(imaxn, dthres);
    ttype = class(m.reg(1, 1, 1));
    stype = parse_type(ttype);
    nsize = pixh * pixw * nf * stype; %%% size of single %%%
    nbatch = batch_compute(nsize);
    ebatch = ceil(nf / nbatch);
    idbatch = [1: ebatch: nf, nf + 1];
    nbatch = length(idbatch) - 1;
    for i = 1: nbatch
        tmp = m.reg(1: pixh, 1: pixw, idbatch(i): idbatch(i + 1) - 1) .* mskpre;
        m.reg(1: pixh, 1: pixw, idbatch(i): idbatch(i + 1) - 1) = tmp;
    end

    %%% get translation score %%%
    fprintf('Begin initial computation of translation score \n')
    nsize = pixh * pixw * nf * stype * 2; %%% size of single in parallel %%%
    nbatch = batch_compute(nsize);
    ebatch = ceil(nf / nbatch);
    idbatch = [1: ebatch: nf, nf + 1];
    nbatch = length(idbatch) - 1;
    acorr = zeros(1, nf - 1);
    for i = 1: nbatch
        tmp = m.reg(1: pixh, 1: pixw, max(1, idbatch(i) - 1): idbatch(i + 1) - 1);
        acorr(max(1, idbatch(i) - 1): idbatch(i + 1) - 2) = get_trans_score(tmp, [], 1, 1);
    end

    %%% cluster movie into hierarchical stable-nonstable sections %%%
    [stt, stp, flag, scl] = hier_clust(acorr, Fs, pixs, scl, stype, m); %%% flag: real or fake clusters %%%
    time = toc(hreg);
    fprintf(['Done initialization, ', num2str(time), ' seconds \n'])

    %% intra-section registration %%
    fprintf('Begin intra-section \n')
    m = intra_section(m, stt, stp, pixs, scl, sigma_x, sigma_f, sigma_d, flag);
    time = toc(hreg);
    fprintf(['Done intra-section, ', num2str(time), ' seconds \n'])

    %% inter-section registration %%
    fprintf('Begin inter-section ... ')
    [m, ~, ~] = inter_section(m, stt, stp, pixs, scl, sigma_x, sigma_f, sigma_d);
    time = toc(hreg);
    fprintf(['Done inter-section, ', num2str(time), ' seconds \n'])

    %% nonstable-section registration %%
    fprintf('Begin nonstable-section \n')
    m = nonstable_section(m, stt, stp, pixs, scl, sigma_x, sigma_f, sigma_d);
    time = toc(hreg);
    fprintf(['Done nonstable-section, ', num2str(time), ' seconds \n'])
        
    %% final preparation for output %%
    %%% final score %%%
    fprintf('Begin final computation of translation score')
    nsize = pixh * pixw * nf * stype * 2; %%% size of single in parallel %%%
    nbatch = batch_compute(nsize);
    ebatch = ceil(nf / nbatch);
    idbatch = [1: ebatch: nf, nf + 1];
    nbatch = length(idbatch) - 1;
    acorrf = zeros(1, nf - 1);
    for i = 1: nbatch
        tmp = m.reg(1: pixh, 1: pixw, max(1, idbatch(i) - 1): idbatch(i + 1) - 1);
        acorrf(max(1, idbatch(i) - 1): idbatch(i + 1) - 2) = get_trans_score(tmp, [], 1, 1);
    end
    time = toc(hreg);
    fprintf(['Done frame reg, total time: ', num2str(time), ' seconds'])
end

