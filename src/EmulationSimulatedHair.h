#pragma once

#include "IDrawable.h"
#include "ResetUtils.h"
#include "RenderItem.h"
#include "EmulationSimulation.h"


class EmulationSimulatedHair : public IDrawable
{
public:
	EmulationSimulatedHair(ID3D11Device *device, ID3D11DeviceContext *context, EmulationSimulation *simulation);
	~EmulationSimulatedHair();

	void Draw(float deltaTime, ID3D11DeviceContext *context);

	void UpdateCamera(ID3D11DeviceContext *context, XMMATRIX view, XMMATRIX proj);

private:

	struct CameraConstantBuffer
	{
		XMMATRIX world;
		XMMATRIX view;
		XMMATRIX proj;
	};

	struct SplineConstantBuffer
	{
		float vertexCount;
		XMFLOAT3 padding;
	};
	
	UINT mVertexCount = 120;


	void InitializeSharedBuffers(ID3D11Device *device, ID3D11DeviceContext *context);
	void InitializeSplineRenderItem(ID3D11Device *device, ID3D11DeviceContext *context);
	void InitializeControlPolygonRenderItem(ID3D11Device *device, ID3D11DeviceContext *context);

	void DrawSplines(const float deltaTime, ID3D11DeviceContext *context);
	void DrawControlPolygon(const float deltaTime, ID3D11DeviceContext *context);

	RenderItem mSplineRenderItem;
	RenderItem mControlPolygonRenderItem;
	EmulationSimulation *mSimulation;
	
	CameraConstantBuffer mConstantBufferData;
	ID3D11Buffer *mCameraCB;

	bool mIsUpdated = false;
};

