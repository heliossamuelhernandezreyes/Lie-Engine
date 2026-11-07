"""Reusable, bank-bound asset sets. Parents are rigid; leaf scale is explicit.

Sets contain references/poses, never duplicate the captured source samples.
Unknown masters, cycles, mirrors, shears and indirect scan scaling fail closed.
"""
import hashlib
import numpy as np
from lie_asset_contract import proper_rotation

def compile_set(document,name,catalog):
    if document.get('schema')!='lie-asset-sets/1' or document.get('bank_sha256')!=catalog['sha256']:raise ValueError('set_bank_identity')
    result=[];seen=set();sets=document['sets'];assets=document['assets']
    def walk(key,R,t,path,parents):
        if key in parents:raise ValueError('set_cycle')
        if key not in sets:raise ValueError('unknown_set')
        for i,node in enumerate(sets[key]['nodes']):
            label=node.get('id',str(i));node_path=path+'/'+label
            if node_path in seen:raise ValueError('duplicate_instance_path')
            seen.add(node_path);local=proper_rotation(np.array(node.get('basis_columns',np.eye(3)),float).T);offset=np.array(node.get('origin',[0,0,0]),float)
            if offset.shape!=(3,) or not np.isfinite(offset).all():raise ValueError('set_position')
            scale=np.array(node.get('scale',[1,1,1]),float)
            if scale.shape!=(3,) or not np.isfinite(scale).all() or (scale<=0).any():raise ValueError('set_scale')
            child_R=R@local;child_t=R@offset+t
            if ('set' in node)==('asset' in node):raise ValueError('set_node_reference')
            if 'set' in node:
                if not np.array_equal(scale,np.ones(3)):raise ValueError('parent_set_must_be_rigid')
                walk(node['set'],child_R,child_t,node_path,parents+(key,));continue
            aid=node['asset']
            if aid not in assets:raise ValueError('unknown_asset')
            asset=assets[aid];master=asset['master']
            if master not in catalog['masters']:raise ValueError('asset_not_resident')
            policy=asset['scale_policy']
            if policy=='rigid' and not np.array_equal(scale,np.ones(3)):raise ValueError('rigid_asset_scale')
            if policy not in ('rigid','authored_positive'):raise ValueError('asset_scale_policy')
            tint=node.get('tint',[1,1,1]);rough=float(node.get('roughness_delta',0))
            if np.shape(tint)!=(3,) or not np.isfinite(tint).all() or min(tint)<0 or max(tint)>2 or not np.isfinite(rough) or abs(rough)>.2:raise ValueError('set_material_modifier')
            payload={k:v for k,v in node.get('properties',{}).items() if k in ('orientation','cut_face','section','row','interval_half_cells','joint_kind','touch_rows','front_reference_m','front_fit_recipe','layer')}
            result.append(dict(**payload,id=node_path,master=master,origin=child_t.tolist(),basis_columns=child_R.T.tolist(),yaw=0.,scale=scale.tolist(),tint=tint,roughness_delta=rough,
                               owner_id=hashlib.sha256((catalog['sha256']+'|'+node_path).encode()).hexdigest(),asset_role=asset['role'],lod=node.get('lod',2)))
    walk(name,np.eye(3),np.zeros(3),name,());return result
